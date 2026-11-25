# frozen_string_literal: true

require "csv"
require "uri"
require "set"

class SearchConsoleCsvImporter
  class InvalidCsv < StandardError; end
  MAX_BYTES = 5.megabytes
  MAX_ROWS = 50_000
  HEADERS = {
    url: ["上位のページ", "ページ", "Top pages", "Page", "Pages"],
    clicks: ["クリック数", "Clicks"], impressions: ["表示回数", "Impressions"],
    ctr: ["CTR", "クリック率"], position: ["掲載順位", "平均掲載順位", "Position", "Average position"]
  }.freeze

  def initialize(current_file:, previous_file: nil, attributes:, catalog: SeoPageCatalog.new)
    @current_file, @previous_file, @attributes, @catalog = current_file, previous_file, attributes, catalog
  end

  def call
    raise InvalidCsv, "対象期間のページ別CSVを選択してください。" unless @current_file.respond_to?(:read)
    report = SearchConsoleImport.new(@attributes)
    report.current_filename = filename(@current_file)
    report.previous_filename = filename(@previous_file) if @previous_file.respond_to?(:read)
    raise InvalidCsv, report.errors.full_messages.join(" ") unless report.valid?

    @paths = @catalog.rows.map { |row| row.fetch(:path) }.to_set
    current, current_stats = parse(@current_file, "対象期間")
    previous, previous_stats = @previous_file.respond_to?(:read) ? parse(@previous_file, "比較期間") : [{}, nil]
    report.statistics = { "current" => current_stats, "previous" => previous_stats }
    SearchConsoleImport.transaction do
      report.save!
      now = Time.current
      [current, previous].each_with_index do |metrics, period|
        rows = metrics.map do |path, values|
          values.merge(search_console_import_id: report.id, period: period, path: path, created_at: now, updated_at: now)
        end
        rows.each_slice(500) { |slice| SearchConsolePageMetric.insert_all!(slice) }
      end
    end
    report
  end

  private

  def filename(file)
    File.basename(file.respond_to?(:original_filename) ? file.original_filename.to_s : "pages.csv").first(255)
  end

  def parse(file, label)
    file.rewind if file.respond_to?(:rewind)
    data = file.read(MAX_BYTES + 1)
    raise InvalidCsv, "#{label}のCSVは5MB以下にしてください。" if data.bytesize > MAX_BYTES
    data = data.force_encoding(Encoding::UTF_8).delete_prefix("\uFEFF")
    raise InvalidCsv, "#{label}のCSVをUTF-8形式で保存してください。" unless data.valid_encoding? && !data.include?("\0")
    csv = CSV.new(data, headers: true, skip_blanks: true)
    first = csv.shift
    raise InvalidCsv, "#{label}のCSVにデータがありません。" unless first
    headers = first.headers.map { |header| header.to_s.strip }
    columns = HEADERS.transform_values { |names| headers.each_index.find { |index| names.any? { |name| name.casecmp?(headers[index]) } } }
    if columns.values.any?(&:nil?) || headers.uniq.length != headers.length || headers.length != 5
      raise InvalidCsv, "#{label}はページ別の通常CSVを選んでください（ページ・クリック数・表示回数・CTR・掲載順位の5列）。日付比較付きCSVは、期間ごとのCSVに分けてください。"
    end
    metrics, seen, total = {}, Set.new, 0
    consume = lambda do |row|
      total += 1
      raise InvalidCsv, "#{label}のCSVは#{MAX_ROWS}行以下にしてください。" if total > MAX_ROWS
      raise InvalidCsv, "#{label}の#{total + 1}行目の列数が正しくありません。" unless row.fields.length == headers.length
      values = columns.transform_values { |index| row.fields[index].to_s.strip }
      url = values.fetch(:url)
      raise InvalidCsv, "#{label}に重複URLがあります（#{total + 1}行目）。ページ別CSVを選んでください。" unless seen.add?(url)
      clicks, impressions = integer(values[:clicks]), integer(values[:impressions])
      ctr = decimal(values[:ctr].delete_suffix("%"))
      position = decimal(values[:position])
      unless clicks && impressions && clicks <= impressions && ctr && ctr.between?(0, 100) && position && (impressions.zero? ? position >= 0 : position > 0)
        raise InvalidCsv, "#{label}の#{total + 1}行目のクリック数・表示回数・CTR・掲載順位を確認してください。"
      end
      begin
        uri = URI.parse(url)
        raise URI::InvalidURIError unless uri.is_a?(URI::HTTP) && uri.host.present?
      rescue URI::InvalidURIError
        raise InvalidCsv, "#{label}の#{total + 1}行目のページURLが正しくありません。"
      end
      # Never merge query variants, redirects or another host's data into a page.
      next unless uri.scheme == "https" && uri.host == "suelog.jp" && uri.port == 443 && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && @paths.include?(uri.path)
      raise InvalidCsv, "#{label}に同じページを指す重複URLがあります。" if metrics.key?(uri.path)
      metrics[uri.path] = { clicks: clicks, impressions: impressions, position: impressions.positive? ? position : nil }
    end
    consume.call(first)
    csv.each { |row| consume.call(row) }
    raise InvalidCsv, "#{label}のCSVにSEOページ一覧と一致するURLがありません。プロパティとページ別CSVをご確認ください。" if metrics.empty?
    [metrics, { "total" => total, "matched" => metrics.length, "unmatched" => total - metrics.length }]
  rescue CSV::MalformedCSVError, ArgumentError, Encoding::CompatibilityError
    raise InvalidCsv, "#{label}のCSVを読み込めません。Search Consoleから書き出したUTF-8のページ別CSVを選んでください。"
  end

  def integer(value)
    return unless value.match?(/\A(?:\d{1,15}|\d{1,3}(?:,\d{3}){1,4})\z/)
    value.delete(",").to_i
  end

  def decimal(value)
    return unless value.match?(/\A\d{1,6}(?:\.\d{1,8})?\z/)
    BigDecimal(value)
  end
end
