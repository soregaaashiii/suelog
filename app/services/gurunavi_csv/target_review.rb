module GurunaviCsv
  class TargetReview
    def self.call(target, action, match: nil, line_number: nil, allow_replace: false)
      batch = GurunaviCsvBatch.metadata.find(target.gurunavi_csv_batch_id)
      mutex = GurunaviCsvWriteLock.create_or_find_by!(name: "registration")
      mutex.with_lock do
        GurunaviCsvWriteLock.where(id: mutex.id).update_all(name: "registration")
        target.with_lock do
          raise Review::Conflict, "照合完了後に操作してください" unless batch.shop_first? && batch.state == "ready"
          raise Review::Conflict, "登録履歴のある店舗は取り消し機能を利用してください" if target.matches.where(state: %w[applied rollback_conflict]).exists?
          shop = Shop.approved.find_by(id: target.shop_id)
          raise Review::Conflict, "店舗が削除・非公開・保留になっています" unless shop
          before = { target_state: target.state, selected_match_id: target.selected_match_id, match_state: match&.state, candidate_states: target.matches.pluck(:id, :state).to_h }
          if %w[exclude restore].include?(action)
            raise Review::Conflict, "登録済みの店舗は除外できません" if GurunaviCsvTarget.registered.where(id: target.id).exists?
            if match && (match.gurunavi_csv_target_id != target.id || match.shop_id != target.shop_id)
              raise Review::Conflict, "この吸えログ店舗の候補ではありません"
            end
            if action == "exclude"
              target.matches.update_all(state: "excluded", allow_replace: false, updated_at: Time.current)
              target.update!(state: "excluded", selected_match_id: nil, excluded_at: Time.current)
            else
              raise Review::Conflict, "除外済みの店舗ではありません" unless target.state == "excluded"
              target.matches.where(state: "excluded").update_all(state: "pending", allow_replace: false, updated_at: Time.current)
              target.update!(state: "pending", selected_match_id: nil, excluded_at: nil)
            end
            match&.reload
          elsif action == "add"
            row = batch.rows.find_by(line_number: line_number)
            raise Review::Conflict, "有効なCSV行番号を指定してください" unless row && row.classification != "invalid" && RestaurantUrlSearch::Provider.new("gurunavi").canonical_url(row.csv_url)
            match = target.matches.create_or_find_by!(gurunavi_csv_row_id: row.id, shop_id: target.shop_id) do |m|
              m.classification = "review"
              m.reason = "管理者がCSV行番号を指定。店名・住所・URLを確認してください。"
              m.shop_snapshot = Snapshot.call(shop)
            end
            target.update!(classification: "review", state: "pending", selected_match_id: nil, reason: "管理者がCSV候補を追加")
          else
            if action == "hold" && match.nil?
              target.matches.where(state: "confirmed").update_all(state: "pending", allow_replace: false)
              target.update!(state: "held", selected_match_id: nil)
            else
              raise Review::Conflict, "この吸えログ店舗の候補ではありません" unless match && match.gurunavi_csv_target_id == target.id && match.shop_id == target.shop_id
              match.lock!
              case action
              when "refresh"
                match.update!(shop_snapshot: Snapshot.call(shop), classification: "review", state: "pending", allow_replace: false, reason: "現在の吸えログ店舗データを再取得。必ず再確認してください。")
                target.update!(shop_snapshot: Snapshot.call(shop), classification: "review", state: "pending", selected_match_id: nil)
              when "confirm"
                raise Review::Conflict, "照合後に店舗データが更新されています。現在データで再確認してください。" unless Snapshot.call(shop) == match.shop_snapshot
                url = RestaurantUrlSearch::Provider.new("gurunavi").canonical_url(match.gurunavi_csv_row.csv_url)
                raise Review::Conflict, "CSV店舗URLが不正です" unless url
                if (shop.gurunavi_url.present? || shop.gurunavi_affiliate_url.present?) && RestaurantUrlSearch::Provider.new("gurunavi").canonical_url(shop.gurunavi_url) != url && !allow_replace
                  raise Review::Conflict, "既存URLの置き換えには競合確認のチェックが必要です"
                end
                target.matches.where(state: "confirmed").where.not(id: match.id).update_all(state: "pending", allow_replace: false)
                match.update!(state: "confirmed", allow_replace: allow_replace)
                target.update!(state: "confirmed", selected_match_id: match.id)
              when "hold"
                match.update!(state: "held", allow_replace: false)
                target.update!(state: "held", selected_match_id: nil)
              else
                raise Review::Conflict, "操作が正しくありません"
              end
            end
          end
          batch.events.create!(gurunavi_csv_match_id: match&.id, gurunavi_csv_row_id: match&.gurunavi_csv_row_id, action: action, payload: { target_id: target.id, shop_id: target.shop_id, before: before, after: { target_state: target.state, selected_match_id: target.selected_match_id, match_state: match&.state, candidate_states: target.matches.pluck(:id, :state).to_h } })
        end
      end
    end
  end
end
