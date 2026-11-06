module HotpepperApi
  # API collection is resumable per Suelog shop. It never writes a shop URL.
  class Importer
    class Superseded < StandardError; end
    class InvalidSearch < StandardError; end

    def initialize(batch, execution, token, client_factory: ->(shop) { RestaurantUrlSearch::HotpepperApi.new(shop) })
      @batch, @execution, @token, @client_factory = batch, execution, token, client_factory
    end

    def checkpoint
      @execution.with_lock do
        raise Superseded unless @execution.run_token == @token && %w[queued running].include?(@execution.state)
        @execution.update!(state: "running", heartbeat_at: Time.current)
        yield
      end
    ensure
      release_connection
    end

    def release_connection
      pool = ActiveRecord::Base.connection_pool
      pool.release_connection unless pool.active_connection?&.transaction_open?
    end

    def call
      raise InvalidSearch, "RenderにHOTPEPPER_API_KEYを設定してください" if ENV["HOTPEPPER_API_KEY"].blank?
      area = Normalizer.name(@batch.area_filter)
      # Freeze the target set on first execution, so restarting doesn't change the denominator.
      if @batch.targets.empty?
        ids = Shop.approved.order(:id).pluck(:id, :address).filter_map do |id, address|
          id if area.blank? || Normalizer.municipality(address).start_with?(area)
        end
        ids = ids.first(100) if @batch.trial_mode?
        checkpoint do
          now = Time.current
          ids.each_slice(500) do |group|
            snapshots = Shop.where(id: group).index_by(&:id)
            HotpepperApiTarget.insert_all!(group.map { |id| { hotpepper_api_batch_id: @batch.id, shop_id: id, classification: "pending", state: "pending", shop_snapshot: Snapshot.call(snapshots.fetch(id)), created_at: now, updated_at: now } })
          end
        end
      end
      checkpoint do
        @batch.update!(state: "processing", phase: "search", target_rows: @batch.targets.count, message: "公式APIで候補を検索中。店舗URLは更新しません。")
        @execution.update!(total_count: @batch.targets.count)
      end
      processed = @batch.targets.where.not(classification: "pending").count
      index = ShopMatcher.shop_index
      @batch.targets.where(classification: "pending").find_in_batches(batch_size: 100) do |targets|
        shops = Shop.approved.where(id: targets.map(&:shop_id)).index_by(&:id)
        targets.each do |target|
          checkpoint { }
          shop = shops[target.shop_id]
          unless shop
            processed += 1
            checkpoint { target.update!(classification: "unmatched", state: "excluded", reason: "店舗が非公開・削除・保留になりました") }
            next
          end
          begin
            # HTTP can take seconds: never reserve a database connection while waiting.
            release_connection
            records = @client_factory.call(shop).records_for_matching
          rescue RestaurantUrlSearch::HotpepperApi::TooManyCandidates => e
            processed += 1
            checkpoint { target.update!(classification: "review", reason: e.message, shop_snapshot: Snapshot.call(shop)) }
            next
          end
          checkpoint do
            rows = records.filter_map do |record|
              url = RestaurantUrlSearch::Provider.new("hotpepper").canonical_url(record.dig("urls", "pc"))
              next unless url && record["name"].present? && record["address"].present?
              @batch.rows.find_or_create_by!(canonical_url: url) do |row|
                row.line_number = (@batch.rows.maximum(:line_number) || 0) + 1
                row.raw_fields = record
                row.raw_row = record.to_json
                row.csv_name, row.csv_address, row.csv_url = record["name"], record["address"], url
                row.normalized_name = Normalizer.name(row.csv_name)
                row.normalized_address = Normalizer.address(row.csv_address)
                row.municipality = Normalizer.municipality(row.csv_address)
              end
            end
            matcher = ShopMatcher.new(@batch.rows.where(id: rows.map(&:id)), index: index)
            classification, reason, found = matcher.call(shop)
            target.update!(classification: classification, state: classification == "registered" ? "skipped" : "pending", reason: reason, shop_snapshot: Snapshot.call(shop), confidence: found.map { |m| m[:confidence] }.max.to_i)
            found.each { |attributes| target.matches.create!(attributes) }
            processed += 1
            count = processed
            @batch.update!(processed_rows: count, total_rows: @batch.rows.count, message: "公式API検索・照合 #{count}/#{@batch.target_rows}店舗")
            @execution.update!(processed_count: count)
          end
        end
      end
      checkpoint do
        @batch.update!(state: "ready", phase: "complete", processed_rows: @batch.targets.count, total_rows: @batch.rows.count, message: "公式APIの検索・照合が完了しました。候補を確認して登録してください。")
        @execution.update!(state: "completed", message: "候補検索完了。店舗URLは未更新です。")
        @batch.events.create!(hotpepper_api_execution_id: @execution.id, action: "matched", payload: { targets: @batch.target_rows, candidates: @batch.total_rows })
      end
    end
  end
end
