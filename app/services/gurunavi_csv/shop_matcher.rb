module GurunaviCsv
  # The result unit is a published Suelog shop. CSV-only restaurants never become targets.
  class ShopMatcher
    MAX_CANDIDATES = 25
    def initialize(rows)
      @exact, @name_city, @street, @grams, @urls = {}, {}, {}, {}, {}
      @duplicates = rows.where.not(normalized_name: [ nil, "" ]).where.not(csv_address: [ nil, "" ]).group(:normalized_name, :normalized_address).count
      @url_counts = rows.where.not(canonical_url: nil).group(:canonical_url).count
      @shop_counts = Shop.where.not(gurunavi_csv_identity_key: nil).group(:gurunavi_csv_identity_key).count
      Shop.where.not(gurunavi_csv_url_key: nil).pluck(:id, :gurunavi_csv_url_key).each { |id, url| add(@urls, url, id) }
      rows.where.not(classification: "invalid").select(:id, :csv_name, :csv_address, :csv_url, :canonical_url, :normalized_name, :normalized_address, :municipality).find_each do |row|
        add(@exact, [ row.normalized_name, row.normalized_address ], row)
        add(@name_city, [ row.normalized_name, row.municipality ], row)
        add(@street, Normalizer.street(row.csv_address), row)
        Normalizer.grams(row.csv_name).each { |gram| add(@grams, [ row.municipality, gram ], row) } if row.municipality.present?
      end
    end
    def add(index, key, value) = (index[key] ||= []) << value
    def provider = @provider ||= RestaurantUrlSearch::Provider.new("gurunavi")
    def call(shop)
      snapshot = Snapshot.call(shop)
      name, address, city = Normalizer.name(shop.name), Normalizer.address(shop.address), Normalizer.municipality(shop.address)
      pool = []
      unless name.blank? || Normalizer.clean_address(shop.address).blank?
        pool = @exact.fetch([ name, address ], []).dup
        if pool.empty?
          pool.concat(@name_city.fetch([ name, city ], []))
          pool.concat(@street.fetch(Normalizer.street(shop.address), []))
          blocks = Normalizer.grams(shop.name).map { |gram| @grams.fetch([ city, gram ], []) }.reject(&:empty?).sort_by(&:size)
          blocks.first(2).each { |block| pool.concat(block.first(200)) }
          pool.uniq!(&:id)
          pool.select! { |row| Confidence.score(shop.name, shop.address, row.csv_name, row.csv_address).positive? }
        end
      end
      scores = pool.to_h { |row| [ row.id, Confidence.score(shop.name, shop.address, row.csv_name, row.csv_address) ] }
      pool.sort_by! { |row| [ -scores.fetch(row.id), row.id ] }
      more = pool.size > MAX_CANDIDATES
      found = pool.first(MAX_CANDIDATES).map do |row|
        exact = row.normalized_name == name && row.normalized_address == address
        reasons = []
        reasons << (row.normalized_name == name ? "店舗名の正規化値一致（支店名を保持）" : "店舗名が異なる・類似候補")
        reasons << (row.normalized_address == address ? "住所全文の正規化値一致" : "住所・番地・建物・階数などに差異または不足")
        reasons << "CSV内の同名・同住所が複数行" if @duplicates[[ row.normalized_name, row.normalized_address ]].to_i > 1
        reasons << "同じCSV店舗URLが複数行" if @url_counts[row.canonical_url].to_i > 1
        identity_count = @shop_counts[Normalizer.identity(shop.name, shop.address)].to_i
        reasons << "吸えログ側で同じ正規化キーが複数店舗" if identity_count > 1
        reasons << "住所の番地などが不足" unless Normalizer.complete?(shop.address) && Normalizer.complete?(row.csv_address)
        classification = if provider.canonical_url(shop.gurunavi_url) == row.canonical_url
          reasons << "同じぐるなびURLが登録済みのため更新しません"
          "registered"
        elsif shop.gurunavi_url.present? || shop.gurunavi_affiliate_url.present? || @urls.fetch(row.canonical_url, []).any? { |id| id != shop.id }
          reasons << "既存URL・アフィリエイトURLまたは他店舗のURL登録と競合"
          "conflict"
        elsif exact && pool.size == 1 && @duplicates[[ name, address ]] == 1 && identity_count == 1 && @url_counts[row.canonical_url] == 1 && Normalizer.complete?(shop.address) && Normalizer.complete?(row.csv_address)
          reasons << "CSV・吸えログ双方で一対一。情報の矛盾なし"
          "bulk"
        else
          "review"
        end
        confidence = scores.fetch(row.id)
        confidence = [ confidence, 200 ].min if pool.size > 1 || @duplicates[[ row.normalized_name, row.normalized_address ]].to_i > 1 || identity_count > 1
        { confidence: confidence, gurunavi_csv_row_id: row.id, shop_id: shop.id, classification: classification, state: classification == "registered" ? "skipped" : "pending", reason: reasons.join(" / "), shop_snapshot: snapshot }
      end
      classification = if found.empty?
        if shop.gurunavi_url.present? || shop.gurunavi_affiliate_url.present?
          provider.canonical_url(shop.gurunavi_url) ? "registered" : "conflict"
        else
          "unmatched"
        end
      elsif found.map { |m| m[:classification] }.uniq == [ "registered" ]
        "registered"
      elsif found.size == 1
        found.first[:classification]
      else
        "review"
      end
      reason = if found.empty?
        text = "この吸えログ店舗に対応する候補がCSV内に見つかりません（ぐるなび未掲載とは判定しません）。"
        text += "既存のURL設定は保持します。" if shop.gurunavi_url.present? || shop.gurunavi_affiliate_url.present?
        text
      else
        found.map { |m| m[:reason] }.uniq.join("\n")
      end
      reason += "\n候補多数のため#{MAX_CANDIDATES}件を表示。CSV行番号で候補を追加できます。" if more
      [ classification, reason, found ]
    end
  end
end
