# frozen_string_literal: true
require "uri"
require "cgi"

class GurunaviAffiliateUrlBuilder
  PREFIX = "https://click.linksynergy.com/deeplink?id=*wLoiMUEEgU&mid=47268&murl=".freeze

  def self.call(url)
    uri = URI.parse(url.to_s.strip)
    unless uri.is_a?(URI::HTTP) && uri.host == "r.gnavi.co.jp" &&
        uri.path.match?(%r{\A/[a-zA-Z0-9]+/?\z}) && uri.userinfo.nil? && uri.port == uri.default_port
      raise ArgumentError, "ぐるなびの店舗URL（https://r.gnavi.co.jp/店舗ID/）を入力してください"
    end
    PREFIX + CGI.escape(uri.to_s)
  rescue URI::InvalidURIError
    raise ArgumentError, "正しいぐるなび店舗URLを入力してください"
  end
end
