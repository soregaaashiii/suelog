module GurunaviCsv
  class RefreshCandidates
    def initialize(execution, token)
      @execution, @token = execution, token
      @batch = execution.gurunavi_csv_batch
    end
    def call
      @execution.with_lock do
        raise Importer::Superseded unless @execution.run_token == @token && %w[queued running].include?(@execution.state)
        @execution.update!(state: "running", heartbeat_at: Time.current, message: "CSV全体の照合索引を作成中")
      end
      matcher = ShopMatcher.new(@batch.rows)
      mutex = GurunaviCsvWriteLock.create_or_find_by!(name: "registration")
      previous_ids = @batch.targets.pluck(:id)
      processed = @execution.kind == "expand" ? expand_targets(matcher) : 0
      @batch.targets.where(id: previous_ids).includes(:matches).find_each do |target|
        @execution.with_lock do
          raise Importer::Superseded unless @execution.run_token == @token && %w[queued running].include?(@execution.state)
          mutex.with_lock do
            GurunaviCsvWriteLock.where(id: mutex.id).update_all(name: "registration")
            target.with_lock do
              shop = Shop.approved.find_by(id: target.shop_id)
              if shop
                classification, reason, found = matcher.call(shop)
                # Preserve all decisions and audit records. Only untouched targets gain new candidates.
                untouched = target.state == "pending" && !target.matches.where.not(state: "pending").exists?
                if untouched
                  found.each do |attributes|
                    match = target.matches.find_or_initialize_by(gurunavi_csv_row_id: attributes[:gurunavi_csv_row_id], shop_id: shop.id)
                    match.assign_attributes(attributes)
                    match.save!
                  end
                  target.update!(classification: classification, reason: reason, shop_snapshot: Snapshot.call(shop))
                end
                target.matches.includes(:gurunavi_csv_row).each do |match|
                  row = match.gurunavi_csv_row
                  score = Confidence.score(shop.name, shop.address, row.csv_name, row.csv_address)
                  score = [ score, 200 ].min if target.matches.size > 1
                  match.update!(confidence: score)
                end
                target.update!(confidence: target.matches.maximum(:confidence).to_i)
              end
            end
          end
          processed += 1
          @execution.update!(state: "running", processed_count: processed, heartbeat_at: Time.current)
        end
      end
      @execution.with_lock do
        raise Importer::Superseded unless @execution.run_token == @token
        @execution.update!(state: "completed", message: "候補の追加照合・確度順への更新が完了しました", heartbeat_at: Time.current)
        @batch.events.create!(gurunavi_csv_execution_id: @execution.id, action: "confidence_refreshed", payload: { target_count: processed })
      end
    end
    def expand_targets(matcher)
      missing = Shop.approved.where.not(id: @batch.targets.select(:shop_id))
      @execution.update!(total_count: @batch.targets.count + missing.count, message: "CSV全体と全エリアの公開店舗を照合中")
      @batch.update!(trial_mode: false, area_filter: nil)
      processed = 0
      missing.select(:id, :name, :address, :gurunavi_url, :gurunavi_affiliate_url, :updated_at).find_in_batches(batch_size: 250) do |shops|
        targets, matches = [], []
        shops.each do |shop|
          classification, reason, found = matcher.call(shop)
          now = Time.current
          targets << { gurunavi_csv_batch_id: @batch.id, shop_id: shop.id, shop_snapshot: Snapshot.call(shop), confidence: found.map { |m| m[:confidence].to_i }.max.to_i, classification: classification, state: classification == "registered" ? "skipped" : "pending", reason: reason, created_at: now, updated_at: now }
          matches.concat(found.map { |m| m.merge(created_at: now, updated_at: now) })
        end
        @execution.with_lock do
          raise Importer::Superseded unless @execution.run_token == @token && %w[queued running].include?(@execution.state)
          GurunaviCsvTarget.insert_all!(targets)
          target_ids = @batch.targets.where(shop_id: shops.map(&:id)).pluck(:shop_id, :id).to_h
          matches.each { |m| m[:gurunavi_csv_target_id] = target_ids.fetch(m[:shop_id]) }
          GurunaviCsvMatch.insert_all!(matches) if matches.any?
          processed += shops.size
          @batch.update!(target_rows: @batch.targets.count, processed_rows: @batch.targets.count)
          @execution.update!(processed_count: processed, heartbeat_at: Time.current)
        end
      end
      processed
    end
  end
end
