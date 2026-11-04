module GurunaviCsv
  class Operations
    def initialize(execution, token)
      @execution, @token = execution, token
      @batch = GurunaviCsvBatch.metadata.find(execution.gurunavi_csv_batch_id)
      @mutex = GurunaviCsvWriteLock.create_or_find_by!(name: "registration")
    end
    def call
      ids = Array(@execution.selection).map(&:to_i)
      processed = 0
      scope = GurunaviCsvMatch.where(id: ids, gurunavi_csv_row_id: @batch.rows.select(:id))
      scope.find_each do |match|
        @execution.with_lock do
          raise Importer::Superseded unless @execution.run_token == @token && %w[queued running].include?(@execution.state)
          @mutex.with_lock do
            GurunaviCsvWriteLock.where(id: @mutex.id).update_all(name: "registration")
            match.with_lock do
              subject = match.gurunavi_csv_target || match.gurunavi_csv_row
              subject.with_lock do
                dispatch(match)
              end
            end
          end
          processed += 1
          @execution.update!(state: "running", processed_count: processed, heartbeat_at: Time.current)
        end
      end
      @execution.with_lock do
        raise Importer::Superseded unless @execution.run_token == @token
        @execution.update!(state: "completed", processed_count: ids.size, heartbeat_at: Time.current, message: "処理完了。競合・スキップは各行で確認してください。")
        @batch.events.create!(gurunavi_csv_execution_id: @execution.id, action: "#{@execution.kind}_completed", payload: { selected_count: ids.size })
        @batch.update!(message: "#{@execution.kind == 'apply' ? '登録' : '取り消し'}処理が完了しました。競合・スキップは各行をご確認ください。")
      end
    end
    def dispatch(match)
      ActiveRecord::Base.transaction(requires_new: true) do
        if @execution.kind == "apply" then apply(match) else rollback(match) end
      end
    rescue ActiveRecord::RecordInvalid => e
      match.reload
      match.gurunavi_csv_row.reload
      match.gurunavi_csv_target&.reload
      conflict(match, "モデル検証で停止しました：#{e.record.errors.full_messages.join(' / ')}", rollback: @execution.kind == "rollback")
    end
    def apply(match)
      return if %w[applied skipped rolled_back rollback_conflict].include?(match.state)
      row = match.gurunavi_csv_row
      subject = match.gurunavi_csv_target || row
      return conflict(match, "照合対象の店舗情報が一致しません") if @batch.shop_first? && (!match.gurunavi_csv_target || subject.gurunavi_csv_batch_id != @batch.id || subject.shop_id != match.shop_id)
      eligible = (match.classification == "bulk" && match.state == "pending" && subject.classification == "bulk" && subject.state == "pending") || (match.state == "confirmed" && subject.selected_match_id == match.id && subject.state == "confirmed")
      return conflict(match, "確認状態が変更されています。再確認してください。") unless eligible
      shop = Shop.find_by(id: match.shop_id)
      return conflict(match, "店舗が削除されています") unless shop
      shop.with_lock do
        return conflict(match, "吸えログ店舗が非公開・保留になりました") if @batch.shop_first? && !Shop.approved.where(id: shop.id).exists?
        return conflict(match, "照合後に店舗データが変更されました。登録せず競合として残します。") unless Snapshot.call(shop) == match.shop_snapshot
        if match.classification == "bulk" && match.state == "pending"
          identity = Normalizer.identity(row.csv_name, row.csv_address)
          return conflict(match, "照合後に同じ正規化キーの店舗が増えたため一対一ではありません") unless identity && Shop.where(gurunavi_csv_identity_key: identity).count == 1
        end
        url = RestaurantUrlSearch::Provider.new("gurunavi").canonical_url(row.csv_url)
        return conflict(match, "ぐるなび店舗詳細URLが不正です") unless url
        return conflict(match, "同じぐるなびURLが他店舗に登録済みです") if Shop.where(gurunavi_csv_url_key: url).where.not(id: shop.id).exists?
        if RestaurantUrlSearch::Provider.new("gurunavi").canonical_url(shop.gurunavi_url) == url
          match.update!(state: "skipped", reason: "同じ店舗URLが登録済みのためスキップ")
          return
        end
        if (shop.gurunavi_url.present? || shop.gurunavi_affiliate_url.present?) && !match.allow_replace?
          return conflict(match, "既存URLとの競合を確認していないため更新しません")
        end
        before = Snapshot.url_values(shop)
        shop.defer_aicoo_activity_delivery = true
        shop.skip_geocoding_for_url_update = true
        shop.update!(gurunavi_url: url, gurunavi_affiliate_url: GurunaviAffiliateUrlBuilder.call(url))
        after = Snapshot.url_values(shop)
        match.update!(state: "applied", before_values: before, after_values: after, applied_version: Snapshot.version(shop), applied_at: Time.current, reason: "管理者確認後に登録しました")
        subject.update!(state: "applied", selected_match_id: match.id)
        event(match, "applied", before: before, after: after, shop_version: match.applied_version)
      end
    end
    def rollback(match)
      return unless %w[applied rollback_conflict].include?(match.state) && match.applied_at.present?
      shop = Shop.find_by(id: match.shop_id)
      return conflict(match, "店舗が削除されているため取り消せません", rollback: true) unless shop
      shop.with_lock do
        unless Snapshot.url_values(shop) == match.after_values && Snapshot.version(shop) == match.applied_version
          return conflict(match, "登録後に別の更新があり、無条件には巻き戻せません。現在値を確認してください。", rollback: true)
        end
        shop.defer_aicoo_activity_delivery = true
        shop.skip_geocoding_for_url_update = true
        shop.update!(match.before_values)
        match.update!(state: "rolled_back", rolled_back_at: Time.current, reason: "今回の登録前のURL値へ取り消しました")
        (match.gurunavi_csv_target || match.gurunavi_csv_row).update!(state: "rolled_back")
        event(match, "rolled_back", before: match.after_values, after: Snapshot.url_values(shop))
      end
    end
    def conflict(match, reason, rollback: false)
      match.update!(state: rollback ? "rollback_conflict" : "conflict", reason: reason)
      (match.gurunavi_csv_target || match.gurunavi_csv_row).update!(state: rollback ? "rollback_conflict" : "conflict")
      event(match, rollback ? "rollback_conflict" : "conflict", reason: reason)
    end
    def event(match, action, payload)
      @batch.events.create!(gurunavi_csv_row_id: match.gurunavi_csv_row_id, gurunavi_csv_match_id: match.id, gurunavi_csv_execution_id: @execution.id, action: action, payload: payload)
    end
  end
end
