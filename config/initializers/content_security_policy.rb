# /Users/kawamuratakuya/dev/suelog/config/initializers/content_security_policy.rb

Rails.application.config.content_security_policy do |p|
  # 基本
  p.default_src :self, :https
  p.base_uri    :self
  p.frame_ancestors :self

  # 画像（Google + ぐるなび追加）
  p.img_src  :self, :https, :data,
             "https://maps.gstatic.com",
             "https://maps.googleapis.com",
             "https://aff.gnavi.co.jp"   # ← これ追加

  # JS（Google Maps）
  p.script_src :self, :https, :unsafe_inline,
               "https://maps.googleapis.com",
               "https://maps.gstatic.com"

  # CSS
  p.style_src :self, :https, :unsafe_inline

  # 通信
  p.connect_src :self, :https,
                "https://maps.googleapis.com",
                "https://maps.gstatic.com"

  # iframe
  p.frame_src :self, :https
end

# 開発ではレポートのみ
Rails.application.config.content_security_policy_report_only = true if Rails.env.development?