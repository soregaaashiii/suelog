require "net/http"
require "json"

module RestaurantUrlSearch
  class SerpApi
    class Unavailable < StandardError; end
    def available? = ENV["SERPAPI_KEY"].present?
    def supports_site_search? = false

    def search(query)
      raise Unavailable, "検索APIが未設定です。Google検索から手動で確認してください。" unless available?
      uri = URI("https://serpapi.com/search.json")
      uri.query = URI.encode_www_form(engine: "google", q: query, api_key: ENV.fetch("SERPAPI_KEY"), hl: "ja", gl: "jp", num: 10)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.get(uri.request_uri) }
      raise Unavailable, "検索APIから正常な応答を取得できませんでした。" unless response.is_a?(Net::HTTPSuccess)
      data = JSON.parse(response.body)
      raise Unavailable, "検索APIがエラーを返しました。時間をおいて再試行してください。" if data["error"].present?
      Array(data["organic_results"]).first(10)
    rescue JSON::ParserError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
      raise Unavailable, "検索APIとの通信に失敗しました。時間をおいて再試行してください。"
    end
  end
end
