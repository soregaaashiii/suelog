module RestaurantUrlSearch
  class Search
    def initialize(shop, provider, client: SerpApi.new, reader: DetailReader.new)
      @shop, @provider, @client, @reader = shop, Provider.new(provider), client, reader
      @queries, @candidates, @visited = [], [], {}
    end

    def call
      return result("unavailable", "検索APIが未設定です。Google検索から手動で確認してください。") unless @client.available?
      Normalization.queries(@shop, @provider).each do |step|
        @queries << step
        found = examine(@client.search(step[:query]))
        return found if found
      end
      if @client.supports_site_search?
        @queries << { stage: "site", query: @shop.name }
        found = examine(@client.site_search(@provider.key, @shop.name))
        return found if found
      end
      result("review", "同一店舗を確認できませんでした。未確認のまま残します。サイト内検索は#{@client.supports_site_search? ? '実施済み' : '未連携'}です。")
    rescue SerpApi::Unavailable => e
      result("unavailable", e.message)
    end

    private
    def examine(results)
      matches = []
      Array(results).first(10).each do |entry|
        next unless entry.is_a?(Hash)
        url = @provider.canonical_url(entry["link"] || entry[:url])
        next unless url
        candidate = @visited[url]
        unless candidate
          evidence = @reader.call(url, @provider)
          matched, reason = CandidateMatcher.call(@shop, evidence)
          candidate = { url: url, matched: matched, reason: reason, evidence: evidence }
          @visited[url] = candidate
          @candidates << candidate
        end
        matches << candidate if candidate[:matched]
      end
      matches.uniq! { |item| item[:url] }
      return result("review", "複数の店舗URLが一致するため、自動登録せず確認を待ちます。") if matches.size > 1
      return result("matched", matches.first[:reason], matches.first[:url]) if matches.one?
      nil
    end

    def result(state, reason, url = nil)
      { state: state, reason: reason, url: url, queries: @queries, candidates: @candidates }
    end
  end
end
