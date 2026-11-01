# frozen_string_literal: true
require "uri"
require "cgi"

class HotpepperAffiliateUrlBuilder
  class ConfigurationMissing < StandardError; end
  DEFAULT_TEMPLATE = "https://ck.jp.ap.valuecommerce.com/servlet/referral?sid=3769275&pid=892606955&vc_url={url_encoded}"
  DEFAULT_VOS = "nhppvccp99002"

  def self.call(url, template: ENV.fetch("HOTPEPPER_AFFILIATE_URL_TEMPLATE", DEFAULT_TEMPLATE))
    uri = URI.parse(url.to_s.strip)
    unless uri.is_a?(URI::HTTP) && (uri.host == "hotpepper.jp" || uri.host.to_s.end_with?(".hotpepper.jp"))
      raise ArgumentError, "ホットペッパーの店舗URLを入力してください"
    end
    unless template.present? && (template.include?("{url_encoded}") || template.include?("{url}"))
      raise ConfigurationMissing, "ホットペッパー用の広告リンク設定が必要です"
    end
    if template == DEFAULT_TEMPLATE
      query = URI.decode_www_form(uri.query.to_s).reject { |key, _| key == "vos" }
      uri.query = URI.encode_www_form(query + [["vos", DEFAULT_VOS]])
    end
    result = template.gsub("{url_encoded}", CGI.escape(uri.to_s)).gsub("{url}", uri.to_s)
    target = URI.parse(result)
    raise ArgumentError, "広告リンクの形式が正しくありません" unless target.is_a?(URI::HTTP) && target.host.present?
    result
  rescue URI::InvalidURIError
    raise ArgumentError, "正しいURLを入力してください"
  end
end
