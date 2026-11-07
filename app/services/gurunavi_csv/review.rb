module GurunaviCsv
  class Review
    class Conflict < StandardError; end
    def self.call(row, action, match: nil, shop_id: nil, allow_replace: false)
      batch = GurunaviCsvBatch.metadata.find(row.gurunavi_csv_batch_id)
      raise Conflict, "吸えログ店舗を起点にした確認画面から操作してください" if batch.shop_first?
      mutex = GurunaviCsvWriteLock.create_or_find_by!(name: "registration")
      mutex.with_lock do
        GurunaviCsvWriteLock.where(id: mutex.id).update_all(name: "registration")
        row.with_lock do
          raise Conflict, "照合完了後に操作してください" unless batch.state == "ready"
          raise Conflict, "不正行・試行対象外の行は確定できません" if %w[invalid out_of_scope].include?(row.classification)
          raise Conflict, "登録履歴のある行は取り消し機能を利用してください" if row.matches.where.not(applied_at: nil).exists?
          if action == "add"
            shop = Shop.find_by(id: shop_id)
            raise Conflict, "店舗IDが見つかりません" unless shop
            match = row.matches.create_or_find_by!(shop_id: shop.id) do |m|
              m.classification = "review"
              m.reason = "管理者が店舗IDを指定。店名・住所の差異と既存URLを確認してください。"
              m.shop_snapshot = Snapshot.call(shop)
            end
            row.update!(classification: "review", state: "pending", reason: "管理者が確認候補を追加")
          else
            raise Conflict, "候補が見つかりません" unless match && match.gurunavi_csv_row_id == row.id
            match.lock!
            before = { state: match.state, snapshot: match.shop_snapshot, allow_replace: match.allow_replace }
            case action
            when "refresh"
              shop = Shop.find_by(id: match.shop_id)
              raise Conflict, "店舗が削除されています" unless shop
              match.update!(shop_snapshot: Snapshot.call(shop), classification: "review", state: "pending", allow_replace: false, reason: "現在の店舗データを再取得。必ず差分を確認して再確定してください。")
              row.update!(classification: "review", state: "pending", selected_match_id: nil)
            when "confirm"
              shop = Shop.find_by(id: match.shop_id)
              raise Conflict, "店舗が削除または照合後に更新されています。現在データで再確認してください。" unless shop && Snapshot.matches?(shop, match.shop_snapshot)
              existing = shop.gurunavi_url.present? || shop.gurunavi_affiliate_url.present?
              target = RestaurantUrlSearch::Provider.new("gurunavi").canonical_url(row.csv_url)
              raise Conflict, "CSV店舗URLが不正です" unless target
              if existing && RestaurantUrlSearch::Provider.new("gurunavi").canonical_url(shop.gurunavi_url) != target && !allow_replace
                raise Conflict, "既存URLの置き換えには競合確認のチェックが必要です"
              end
              row.matches.where(state: "confirmed").where.not(id: match.id).update_all(state: "pending", allow_replace: false)
              match.update!(state: "confirmed", allow_replace: allow_replace)
              row.update!(state: "confirmed", selected_match_id: match.id)
            when "exclude", "hold"
              match.update!(state: action == "exclude" ? "excluded" : "held", allow_replace: false)
              row.update!(state: action == "hold" ? "held" : "pending", selected_match_id: row.selected_match_id == match.id ? nil : row.selected_match_id)
              row.update!(state: "excluded") unless row.matches.where.not(state: "excluded").exists?
            else
              raise Conflict, "操作が正しくありません"
            end
          end
          batch.events.create!(gurunavi_csv_row_id: row.id, gurunavi_csv_match_id: match&.id, action: action, payload: { before: before, after: { state: match&.state, snapshot: match&.shop_snapshot, allow_replace: match&.allow_replace } })
        end
      end
    end
  end
end
