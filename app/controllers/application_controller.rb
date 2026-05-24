# /Users/kawamuratakuya/dev/suelog/app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
# Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
allow_browser versions: :modern

# Changes to the importmap will invalidate the etag for HTML responses
stale_when_importmap_changes

helper_method :page_view_tracking_excluded?

# --- アクセス計測（PV/UU/流入/ボット除外/自端末除外） ---
private

def track_page_view(shop: nil)
return if page_view_tracking_excluded?

ua = request.user_agent.to_s
return if bot_user_agent?(ua)

# IPは個人情報になりやすいので、生IPは保存しない（ハッシュ化）
raw_ip = request.remote_ip.to_s

# “毎日変わるsalt” を混ぜて、長期追跡にならない疑似UUにする（プライバシー寄り）
salt = "suelog-uu-#{Date.current}"
ip_hash = Digest::SHA256.hexdigest("#{raw_ip}|#{ua}|#{salt}")

ref = request.referer.to_s

return if PageView.where(
shop: shop,
path: request.path,
ip_hash: ip_hash,
created_at: Time.current.beginning_of_day..Time.current.end_of_day
).exists?

PageView.create!(
shop: shop,
path: request.path,
ip_hash: ip_hash,
user_agent: ua,
referrer: ref.presence,
utm_source: params[:utm_source],
utm_medium: params[:utm_medium],
utm_campaign: params[:utm_campaign],
is_bot: false
)
rescue => e
# アクセス計測失敗で本機能が落ちないように握りつぶす（ログだけ）
Rails.logger.warn("[track_page_view] #{e.class}: #{e.message}")
end

def page_view_tracking_excluded?
cookies.signed[:exclude_page_views].to_s == "1"
end

def bot_user_agent?(ua)
u = ua.to_s.downcase

# 超簡易：主要クローラと一般的なbot文字列を弾く
bot_keywords = %w[
bot crawl spider slurp bingpreview duckduckbot yandex
googlebot baiduspider facebookexternalhit twitterbot
embedly pinterest
]

bot_keywords.any? { |k| u.include?(k) }
end
# --- /アクセス計測 ---
end