class RestaurantUrlSearchJob < ApplicationJob
  def perform(run_id, token)
    run = RestaurantUrlSearchRun.find_by(id: run_id, run_token: token)
    return unless run && run.state == "pending"
    shop = run.shop
    result = RestaurantUrlSearch::Search.new(shop, run.provider).call
    run.with_lock do
      return unless run.run_token == token && run.state == "pending"
      shop.with_lock do
        if run.input_digest != RestaurantUrlSearchRun.input_digest(shop, run.provider)
          result = result.merge(state: "review", reason: "検索中に店舗情報・URLが変更されたため保存しませんでした。再確認してください。")
        elsif result[:state] == "matched"
          provider = RestaurantUrlSearch::Provider.new(run.provider)
          url = provider.canonical_url(result[:url])
          if url && shop.public_send("#{run.provider}_url").blank? && shop.public_send("#{run.provider}_affiliate_url").blank?
            shop.defer_aicoo_activity_delivery = true
            shop.skip_geocoding_for_url_update = true
            shop.update!("#{run.provider}_url" => url, "#{run.provider}_affiliate_url" => provider.affiliate_url(url))
          else
            result = result.merge(state: "review", reason: "既存URLは上書きしません。店舗情報を確認してください。")
          end
        end
        run.update!(state: result[:state], payload: result, input_digest: RestaurantUrlSearchRun.input_digest(shop, run.provider))
      end
    end
  rescue StandardError => e
    # Never store network exception messages, which may contain API credentials.
    RestaurantUrlSearchRun.where(id: run_id, run_token: token, state: "pending").update_all(state: "unavailable", payload: { reason: "検索処理を完了できませんでした。未確認のまま再試行してください。" }.to_json, updated_at: Time.current)
    Rails.logger.warn("[RestaurantUrlSearchJob] #{e.class}")
  end
end
