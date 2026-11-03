require "uri"

module RestaurantUrlSearch
  class Provider
    CONFIG = {
      "gurunavi" => { label: "ぐるなび", domain: "r.gnavi.co.jp", path: %r{\A/[a-z0-9]{6,32}/?\z}i, builder: "GurunaviAffiliateUrlBuilder" },
      "hotpepper" => { label: "ホットペッパー", domain: "www.hotpepper.jp", path: %r{\A/strJ\d{9}/?\z}, builder: "HotpepperAffiliateUrlBuilder" }
    }.freeze

    attr_reader :key
    def initialize(key)
      @key = key.to_s
      @config = CONFIG.fetch(@key) { raise ArgumentError, "対応していない検索サイトです" }
    end

    def label = @config[:label]
    def domain = @config[:domain]
    def affiliate_url(url) = @config[:builder].constantize.call(url)

    def canonical_url(url)
      uri = URI.parse(url.to_s.strip)
      return unless uri.is_a?(URI::HTTP) && uri.userinfo.nil? && uri.port == uri.default_port
      host = uri.host.to_s.downcase
      host = "www.hotpepper.jp" if key == "hotpepper" && host == "hotpepper.jp"
      return unless host == domain && uri.path.match?(@config[:path])
      return if key == "gurunavi" && %w[search category restaurant restaurants index ranking].include?(uri.path.delete("/"))
      "https://#{domain}#{uri.path.sub(%r{/?$}, '/')}"
    rescue URI::InvalidURIError
      nil
    end
  end
end
