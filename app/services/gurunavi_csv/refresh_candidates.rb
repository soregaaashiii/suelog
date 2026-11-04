module GurunaviCsv
  class RefreshCandidates
    def initialize(execution, token)
      @execution, @token = execution, token
      @batch = execution.gurunavi_csv_batch
    end
    def call
      matcher = ShopMatcher.new(@batch.rows)
      mutex = GurunaviCsvWriteLock.create_or_find_by!(name: "registration")
      processed = 0
      @batch.targets.includes(:matches).find_each do |target|
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
  end
end
