# frozen_string_literal: true

class ShopKeywordSearch
  FIELDS = %i[name address area nearest_station phone public_store_details genre genre_other opening_hours_text holiday_hours_text closed_days_text].freeze
  ALIASES = [
    %w[難波 なんば], %w[梅田 うめだ], %w[江坂 えさか], %w[心斎橋 しんさいばし],
    %w[中百舌鳥 なかもず], %w[三国ヶ丘 三国ケ丘 三国が丘 みくにがおか],
    %w[天王寺 てんのうじ], %w[北新地 きたしんち],
    %w[居酒屋 いざかや], %w[焼き鳥 焼鳥 やきとり], %w[焼肉 焼き肉 やきにく], %w[喫茶店 きっさてん]
  ].freeze

  def self.base(value)
    value.to_s.unicode_normalize(:nfkc).downcase.tr("ァ-ヶ", "ぁ-ゖ").tr("髙﨑ゕゖ", "高崎かけ")
      .gsub(/[^\p{L}\p{M}\p{N}]/, "")
  end

  ALIAS_MAP = ALIASES.each_with_object({}) do |group, result|
    group.each { |value| result[base(value)] = base(group.first) }
  end.freeze
  ALIAS_PATTERN = Regexp.union(ALIAS_MAP.keys.sort_by { |key| -key.length }).freeze

  def self.normalize(value)
    base(value).gsub(ALIAS_PATTERN) { |word| ALIAS_MAP.fetch(word) }
  end

  def self.tokens(value)
    text = value.to_s.unicode_normalize(:nfkc)
    words = text.split(/[^\p{L}\p{M}\p{N}]+/).reject(&:empty?).map { |word| normalize(word) }
    words.empty? && text.present? ? [""] : words
  end

  def self.document(values)
    values.map { |value| normalize(value) }.join("\n")
  end

  def self.apply(scope, value, station: false)
    return scope if value.to_s.blank?
    tokens(value).reduce(scope) { |result, token| apply_token(result, token, station: station) }
  end

  def self.apply_token(scope, keyword, station: false)
    return scope.none if keyword.empty?
    # Bulk inserts without callbacks remain searchable until their projection is rebuilt.
    column = station ? :keyword_station_text : :keyword_search_text
    fields = station ? [:nearest_station] : FIELDS
    missing_ids = scope.where(column => nil).pluck(:id, *fields).filter_map do |id, *values|
      id if document(values).include?(keyword)
    end
    normalized = scope.where("shops.#{column} LIKE ? ESCAPE '\\'", "%#{Shop.sanitize_sql_like(keyword)}%")
    missing_ids.empty? ? normalized : normalized.or(scope.where(id: missing_ids))
  end
end
