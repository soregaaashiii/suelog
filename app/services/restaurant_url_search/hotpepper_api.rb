require "net/http"
require "json"

module RestaurantUrlSearch
  class HotpepperApi
    def initialize(shop)
      @shop = shop
    end

    def call
      provider = Provider.new("hotpepper")
      candidates = {}
      queries = []
      steps = [ { stage: "name", name: @shop.name } ]
      phone = Normalization.phone(@shop.phone)
      steps << { stage: "phone", tel: phone } if phone.present?
      steps.each do |step|
        queries << { stage: step[:stage], query: step[:name] || step[:tel] }
        records = fetch(step.except(:stage))
        matches = []
        records.each do |record|
          url = provider.canonical_url(record.dig("urls", "pc"))
          next unless url
          evidence = { name: record["name"], address: record["address"], phone: step[:tel] }
          matched, reason = CandidateMatcher.call(@shop, evidence)
          candidate = { url: url, matched: matched, reason: reason, evidence: evidence }
          candidates[url] = candidate
          matches << candidate if matched
        end
        return result("review", "複数の店舗が一致するため確認してください。", queries, candidates) if matches.size > 1
        return result("matched", matches.first[:reason], queries, candidates, matches.first[:url]) if matches.one?
      end
      result("review", "公式APIで同一店舗を確定できませんでした。候補を確認してください。", queries, candidates)
    rescue SerpApi::Unavailable => e
      result("unavailable", e.message, queries || [], candidates || {})
    end

    # Candidate retrieval only: bulk registration always waits for administrator review.
    def records_for_matching
      return [] if @shop.name.blank?
      city = Normalization.municipality(@shop.address)
      steps = []
      steps << { keyword: [ @shop.name, city ].compact.join(" ") } if city.present?
      phone = Normalization.phone(@shop.phone)
      steps << { tel: phone } if phone.present?
      steps << { name: @shop.name }
      records = {}
      steps.each do |params|
        fetch_all(params).each do |record|
          records[record["id"] || record.dig("urls", "pc")] = record
        end
        exact = records.values.select do |record|
          GurunaviCsv::Confidence.score(@shop.name, @shop.address, record["name"], record["address"]) == 400
        end
        break if exact.one?
      end
      records.values
    end

    private

    def fetch(params)
      data = fetch_page(params)
      raise SerpApi::Unavailable, "候補が100件を超えました。店舗名を絞って再確認してください。" if data["results_available"].to_i > 100
      Array(data["shop"])
    end

    def fetch_all(params)
      first = fetch_page(params.merge(start: 1))
      total = first["results_available"].to_i
      # Do not silently truncate a broad query and imply that it is exhaustive.
      raise TooManyCandidates, "候補が1,000件を超えたため検索を完了できません。個別に確認してください。" if total > 1000
      records = Array(first["shop"])
      (101..total).step(100) do |start|
        page = fetch_page(params.merge(start: start))
        records.concat(Array(page["shop"]))
      end
      records
    end

    class TooManyCandidates < SerpApi::Unavailable; end

    def fetch_page(params)
      uri = URI("https://webservice.recruit.co.jp/hotpepper/gourmet/v1/")
      uri.query = URI.encode_www_form(params.merge(key: ENV.fetch("HOTPEPPER_API_KEY"), format: "json", count: 100))
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 15) { |http| http.get(uri.request_uri) }
      raise SerpApi::Unavailable, "ホットペッパー公式APIから正常な応答を取得できませんでした。" unless response.is_a?(Net::HTTPSuccess)
      data = JSON.parse(response.body).fetch("results")
      raise SerpApi::Unavailable, "ホットペッパーAPIの設定・利用状況を確認してください。" if data["error"].present?
      data
    rescue JSON::ParserError, KeyError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
      raise SerpApi::Unavailable, "ホットペッパー公式APIとの通信に失敗しました。キーの設定と通信状況を確認してください。"
    end

    def result(state, reason, queries, candidates, url = nil)
      { state: state, reason: reason, url: url, queries: queries, candidates: candidates.values }
    end
  end
end
