module GurunaviCsv
  class Matcher
    MAX_CANDIDATES = 25
    def initialize(rows)
      @exact, @name_city, @street, @grams, @urls = {}, {}, {}, {}, {}
      Shop.select(:id, :name, :address, :gurunavi_url, :gurunavi_affiliate_url, :updated_at).find_each do |shop|
        url = provider.canonical_url(shop.gurunavi_url)
        add(@urls, url, shop.id) if url
        n, a, city = Normalizer.name(shop.name), Normalizer.address(shop.address), Normalizer.municipality(shop.address)
        next if n.blank? || Normalizer.clean_address(shop.address).blank?
        item = { snapshot: Snapshot.call(shop), name: n, address: a, city: city }
        add(@exact, [n,a], item)
        add(@name_city, [n,city], item)
        add(@street, Normalizer.street(shop.address), item)
        Normalizer.grams(n).each { |gram| add(@grams, [city,gram], item) } if city.present?
      end
      valid = rows.where.not(normalized_name: [nil, ""]).where.not(csv_address: [nil, ""])
      @duplicates = valid.group(:normalized_name, :normalized_address).count
      @url_counts = rows.where.not(canonical_url: nil).group(:canonical_url).count
    end
    def provider = @provider ||= RestaurantUrlSearch::Provider.new("gurunavi")
    def add(index, key, value) = (index[key] ||= []) << value

    def call(row)
      exact = @exact.fetch([row.normalized_name, row.normalized_address], [])
      pool = exact.dup
      if exact.empty?
        pool.concat(@name_city.fetch([row.normalized_name, row.municipality], []))
        pool.concat(@street.fetch(Normalizer.street(row.csv_address), []))
        blocks = Normalizer.grams(row.csv_name).map { |gram| @grams.fetch([row.municipality,gram], []) }.reject(&:empty?).sort_by(&:size)
        blocks.first(2).each { |block| pool.concat(block.first(200)) }
      end
      pool.uniq! { |item| item[:snapshot]["id"] }
      pool.select! do |item|
        exact.include?(item) || item[:name] == row.normalized_name || item[:address] == row.normalized_address ||
          (item[:city] == row.municipality && Normalizer.similarity(item[:name], row.csv_name) >= 0.7)
      end
      # Exact matches stay first; omitted suggestions are explicitly reported.
      more = pool.size > MAX_CANDIDATES
      candidates = pool.first(MAX_CANDIDATES).map do |item|
        snapshot = item[:snapshot]
        exact_match = item[:name] == row.normalized_name && item[:address] == row.normalized_address
        reasons = []
        reasons << (item[:name] == row.normalized_name ? "店舗名の正規化値一致（支店名を保持）" : "店舗名が異なる・類似候補")
        reasons << (item[:address] == row.normalized_address ? "住所全文の正規化値一致" : "住所・番地・建物・階数などに差異または不足")
        reasons << "CSV内の同名・同住所が#{@duplicates[[row.normalized_name,row.normalized_address]]}行" if @duplicates[[row.normalized_name,row.normalized_address]].to_i > 1
        reasons << "同じCSV店舗URLが#{@url_counts[row.canonical_url]}行" if @url_counts[row.canonical_url].to_i > 1
        reasons << "吸えログ側で同じ正規化キーが#{exact.size}店舗" if exact.size > 1
        reasons << "住所の番地などが不足" unless Normalizer.complete?(row.csv_address) && Normalizer.complete?(snapshot["address"])
        classification = if snapshot["gurunavi_url"].present? && provider.canonical_url(snapshot["gurunavi_url"]) == row.canonical_url
          reasons << "同じ店舗URLが登録済みのため更新しません"
          "registered"
        elsif snapshot["gurunavi_url"].present? || snapshot["gurunavi_affiliate_url"].present? || @urls.fetch(row.canonical_url, []).any? { |id| id != snapshot["id"] }
          reasons << "既存URL・アフィリエイトURLまたは他店舗のURL登録と競合"
          "conflict"
        elsif exact_match && exact.size == 1 && @duplicates[[row.normalized_name,row.normalized_address]] == 1 && @url_counts[row.canonical_url] == 1 && Normalizer.complete?(row.csv_address) && Normalizer.complete?(snapshot["address"])
          reasons << "CSV・吸えログ双方で一対一。情報の矛盾なし"
          "bulk"
        else
          "review"
        end
        { shop_id: snapshot["id"], classification: classification, state: classification == "registered" ? "skipped" : "pending", reason: reasons.join(" / "), shop_snapshot: snapshot }
      end
      classification = if candidates.empty? then "unmatched"
      elsif candidates.size > 1 then "review"
      else candidates.first[:classification]
      end
      # A single CSV row with several possibilities must never carry a bulk candidate.
      if candidates.size > 1
        candidates.each { |c| c[:classification] = "review" if c[:classification] == "bulk" }
      end
      reason = candidates.empty? ? "同一店舗と判断できる候補がありません（未掲載とは判定しません）" : candidates.map { |c| "店舗#{c[:shop_id]}: #{c[:reason]}" }.join("\n")
      reason += "\n候補多数のため先頭#{MAX_CANDIDATES}件を表示。必要に応じて店舗IDを指定してください。" if more
      [classification, reason, candidates]
    end
  end
end
