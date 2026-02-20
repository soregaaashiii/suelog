# config/initializers/content_security_policy.rb

Rails.application.config.content_security_policy do |p|
  # 基本
  p.default_src :self, :https
  p.base_uri    :self
  p.frame_ancestors :self

  # 画像（Googleのタイル等）
  p.img_src  :self, :https, :data, "https://maps.gstatic.com", "https://maps.googleapis.com"

  # JS（Google Maps）
  p.script_src :self, :https, :unsafe_inline,
               "https://maps.googleapis.com",
               "https://maps.gstatic.com"

  # CSS（Googleが内部で使うことあり）
  p.style_src :self, :https, :unsafe_inline

  # XHR（位置情報・必要な通信）
  p.connect_src :self, :https, "https://maps.googleapis.com", "https://maps.gstatic.com"

  # iframe（今回は使ってないけど将来用）
  p.frame_src :self, :https
end

# 開発ではレポートのみ（ブロックしない）
Rails.application.config.content_security_policy_report_only = true if Rails.env.development?
