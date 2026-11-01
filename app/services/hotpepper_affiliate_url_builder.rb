# frozen_string_literal: true
require "uri"
require "cgi"

class HotpepperAffiliateUrlBuilder
  class ConfigurationMissing < StandardError; end

  def self.call(url, template: ENV["HOTPEPPER_AFFILIATE_URL_TEMPLATE"])
    uri = URI.parse(url.to_s.strip)
    unless uri.is_a?(URI::HTTP) && (uri.host == "hotpepper.jp" || uri.host.to_s.end_with?(".hotpepper.jp"))
      raise ArgumentError, "ホットペッパーの店舗URLを入力してください"
    end
    unless template.present? && (template.include?("{url_encoded}") || template.include?("{url}"))
      raise ConfigurationMissing, "ホットペッパー用の広告リンク設定が必要です"
    end
    result = template.gsub("{url_encoded}", CGI.escape(uri.to_s)).gsub("{url}", uri.to_s)
    target = URI.parse(result)
    raise ArgumentError, "広告リンクの形式が正しくありません" unless target.is_a?(URI::HTTP) && target.host.present?
    result
  rescue URI::InvalidURIError
    raise ArgumentError, "正しいURLを入力してください"
  end
end
