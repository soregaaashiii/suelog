require "csv"
require "stringio"
module GurunaviCsv
  class Importer
    HEADERS = [ "店舗名", "店舗URL", "住所", "営業時間", "ジャンル（大）", "ジャンル（小）" ].freeze
    MAX_ROWS = 100_000
    class InvalidCsv < StandardError; end
    class Superseded < StandardError; end
    def initialize(batch, execution, token)
      @batch, @execution, @token = batch, execution, token
    end
    def checkpoint
      @execution.with_lock do
        raise Superseded unless @execution.run_token == @token && %w[queued running].include?(@execution.state)
        @execution.update!(state: "running", heartbeat_at: Time.current)
        yield
      end
    end
    def call
      checkpoint do
        raise InvalidCsv, "すでに登録履歴があるため再照合できません" if @batch.rows.joins(:matches).where.not(gurunavi_csv_matches: { applied_at: nil }).exists?
        ids = @batch.rows.select(:id)
        GurunaviCsvMatch.where(gurunavi_csv_row_id: ids).delete_all
        @batch.rows.delete_all
        @batch.update!(state: "processing", phase: "decode", processed_rows: 0, message: "CP932を検証中")
      end
      utf8 = +""
      @batch.source_bytes.b.each_line.with_index(1) do |bytes, line|
        begin
          decoded = bytes.dup.force_encoding(Encoding::Windows_31J).encode(Encoding::UTF_8)
          raise InvalidCsv, "行#{line}: NUL文字を含むため取り込みを中止しました。" if decoded.include?("\0")
          utf8 << decoded
        rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
          raise InvalidCsv, "行#{line}: CP932として解読できない文字があります。置換せず取り込みを中止しました。"
        end
      end
      records = parse_records(utf8)
      header_record = records.shift
      header = header_record && header_record[0]
      raise InvalidCsv, "行1: ヘッダーがありません" unless header
      normalized_header = header.map { |v| v.to_s.strip }
      missing = HEADERS - normalized_header
      duplicates = normalized_header.tally.select { |_, count| count > 1 }.keys
      raise InvalidCsv, "行1: 必須ヘッダー不足：#{missing.join('、')} / 重複：#{duplicates.join('、')}" if missing.any? || duplicates.any?
      physical_line = 1
      buffer, total = [], 0
      provider = RestaurantUrlSearch::Provider.new("gurunavi")
      records.each do |fields, raw, line_number, parse_error|
        physical_line = line_number
        total += 1
        raise InvalidCsv, "行#{line_number}: 上限#{MAX_ROWS}件を超えています" if total > MAX_ROWS
        values = normalized_header.zip(fields).to_h
        name, address, url = values.values_at("店舗名", "住所", "店舗URL").map(&:to_s)
        canonical = provider.canonical_url(url)
        errors = []
        errors << "CSVの構造が不正です：#{parse_error}" if parse_error
        errors << "列数がヘッダーと一致しません" unless fields.size == normalized_header.size
        errors << "店舗名が空欄です" if Normalizer.name(name).blank?
        errors << "住所が空欄または郵便番号のみです" if Normalizer.clean_address(address).blank?
        errors << "ぐるなびの店舗詳細URLではありません" unless canonical
        now = Time.current
        buffer << { gurunavi_csv_batch_id: @batch.id, line_number: line_number, raw_row: raw, raw_fields: values, csv_name: name, csv_address: address, csv_url: url, canonical_url: canonical,
          normalized_name: Normalizer.name(name), normalized_address: Normalizer.address(address), municipality: Normalizer.municipality(address), classification: errors.empty? ? "pending" : "invalid", state: "pending", reason: errors.join(" / "), created_at: now, updated_at: now }
        if buffer.size >= 500
          save_rows(buffer, total)
          buffer = []
        end
      end
      save_rows(buffer, total) if buffer.any?
      checkpoint { @batch.update!(total_rows: total, phase: "match", processed_rows: 0, message: "照合用の索引を作成中") }
      matcher = Matcher.new(@batch.rows)
      scoped = @batch.rows.where.not(classification: "invalid")
      scoped = scoped.where("municipality LIKE ?", "#{ActiveRecord::Base.sanitize_sql_like(Normalizer.name(@batch.area_filter))}%") if @batch.area_filter.present?
      target_ids = @batch.trial_mode? ? scoped.order(:line_number).limit(100).pluck(:id) : nil
      targets = target_ids ? scoped.where(id: target_ids) : scoped
      checkpoint do
        @batch.rows.where.not(classification: "invalid").update_all(classification: "out_of_scope", reason: "試行100件または指定エリアの対象外")
        @batch.update!(target_rows: targets.count, message: "照合中")
        @execution.update!(total_count: targets.count, processed_count: 0)
      end
      processed = 0
      targets.find_in_batches(batch_size: 250) do |rows|
        updates, candidates = [], []
        rows.each do |row|
          classification, reason, found = matcher.call(row)
          updates << row.attributes.merge("classification"=>classification, "state"=>classification == "registered" ? "skipped" : "pending", "reason"=>reason, "updated_at"=>Time.current)
          found.each { |candidate| candidates << candidate.merge(gurunavi_csv_row_id: row.id, created_at: Time.current, updated_at: Time.current) }
        end
        processed += rows.size
        checkpoint do
          GurunaviCsvRow.upsert_all(updates, unique_by: :id)
          GurunaviCsvMatch.insert_all(candidates) if candidates.any?
          @batch.update!(processed_rows: processed, message: "照合 #{processed}/#{@batch.target_rows}件")
          @execution.update!(processed_count: processed)
        end
      end
      checkpoint do
        @batch.update!(state: "ready", phase: "complete", message: "照合完了。店舗URLはまだ変更していません。")
        @execution.update!(state: "completed", message: "照合完了")
        GurunaviCsvEvent.create!(gurunavi_csv_batch: @batch, gurunavi_csv_execution_id: @execution.id, action: "matched", payload: { total_rows: total, target_rows: @batch.target_rows })
      end
    rescue CSV::MalformedCSVError => e
      raise InvalidCsv, "行#{(physical_line || 0) + 1}: CSVの構造が不正です。#{e.message}"
    end
    # Recover only independently bounded physical records. Never repair or infer fields.
    def parse_records(text)
      records = []
      parser = CSV.new(StringIO.new(text), liberal_parsing: false)
      physical = 1
      begin
        parser.each do |fields|
          raw = parser.line
          records << [ fields, raw, physical, nil ]
          physical += [ raw.count("\n"), 1 ].max
        end
        records
      rescue CSV::MalformedCSVError => original
        # An odd quote count can mean a multiline record; recovery is unsafe then.
        lines = text.lines
        if lines.any? { |line| line.count('"').odd? }
          raise InvalidCsv, "行#{physical}: CSVの構造が不正です。#{original.message}"
        end
        lines.each_with_index.map do |raw, index|
          begin
            [ CSV.parse_line(raw, liberal_parsing: false), raw, index + 1, nil ]
          rescue CSV::MalformedCSVError => error
            [ [], raw, index + 1, error.message ]
          end
        end
      end
    end
    def save_rows(buffer, total)
      checkpoint do
        GurunaviCsvRow.insert_all!(buffer)
        @batch.update!(processed_rows: total, phase: "parse", message: "CSV #{total}行を読み込み済み")
      end
    end
  end
end
