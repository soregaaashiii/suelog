# frozen_string_literal: true

class GeographicFacets
  GENRES = {
    "izakaya" => { "label" => "居酒屋", "terms" => ["居酒屋"] },
    "cafe" => { "label" => "カフェ・喫茶店", "terms" => ["カフェ", "喫茶店"] },
    "bar" => { "label" => "バー・パブ", "terms" => ["バー", "パブ"] },
    "yakiniku" => { "label" => "焼肉", "terms" => ["焼肉"] },
    "yakitori" => { "label" => "焼き鳥", "terms" => ["焼き鳥", "焼鳥"] },
    "ramen" => { "label" => "ラーメン", "terms" => ["ラーメン"] },
    "sushi" => { "label" => "寿司", "terms" => ["寿司"] },
    "washoku" => { "label" => "和食・日本料理", "terms" => ["和食", "日本料理"] }
  }.freeze
  SMOKING = {
    "seat-smoking" => { "label" => "席で喫煙可" },
    "smoking-room" => { "label" => "喫煙所あり" },
    "heated-only" => { "label" => "加熱式のみ対応" }
  }.freeze
  SMOKING_COLUMNS = %i[smoking_area smoking_type smoking_area_2 smoking_type_2 smoking_condition_schedules smoking_unverified].freeze
  MIN_DIFFERENCE = 3
  MAX_PARENT_SHARE = 0.9

  def initialize(directory = GeographicDirectory.new)
    @directory = directory
  end

  def definitions
    [ ["genre", GENRES], ["smoking", SMOKING] ].flat_map { |kind, configs| configs.map { |slug, config| config.merge("kind" => kind, "slug" => slug) } }
  end

  def definition(kind, slug)
    definitions.find { |facet| facet.fetch("kind") == kind && facet.fetch("slug") == slug }
  end

  def self.keys_for(row)
    tokens = ShopGenreFilter.tokens(row[:genre], row[:genre_other])
    genres = GENRES.filter_map { |slug, config| "genre/#{slug}" if (tokens & config.fetch("terms")).any? }
    genres + smoking_keys(row)
  end

  # Match the public badges: legacy secondary fields are not displayed unless
  # advanced schedules are active. Time restrictions remain on each shop card.
  def self.smoking_keys(row)
    return [] unless row[:smoking_unverified] == false
    rules = row[:smoking_condition_schedules].to_h
    advanced = rules.values.any? { |rule| rule.to_h["mode"].present? || rule.to_h["situation_note"].present? }
    conditions = [[row[:smoking_area], row[:smoking_type], rules["primary"].to_h]]
    if advanced && (row[:smoking_area_2].present? || row[:smoking_type_2].present?)
      conditions << [row[:smoking_area_2], row[:smoking_type_2], rules["secondary"].to_h]
    end
    usable = conditions.reject { |_area, _type, rule| rule["situation_note"].present? }
    keys = []
    keys << "smoking/seat-smoking" if usable.any? { |area, _type, _rule| [1, "all_smoking"].include?(area) }
    keys << "smoking/smoking-room" if usable.any? { |area, _type, _rule| [0, "separated"].include?(area) }
    if conditions.all? { |area, type, rule| [0, 1, "separated", "all_smoking"].include?(area) && [1, "electronic_only"].include?(type) && rule["situation_note"].blank? }
      keys << "smoking/heated-only"
    end
    keys
  end

  def key(facet) = "#{facet.fetch('kind')}/#{facet.fetch('slug')}"
  def path(entry, facet) = "#{@directory.path(entry)}/#{key(facet)}"

  def stats(entry, facet)
    @directory.stats(entry).fetch("facets").fetch(key(facet), { "count" => 0, "ids" => [], "genres" => {} })
  end

  def scope(entry, facet)
    base = @directory.scope(entry)
    return ShopGenreFilter.apply(base, facet.fetch("terms")) if facet.fetch("kind") == "genre"

    # Recheck current conditions, including shops updated during the statistics TTL.
    ids = base.reorder(nil).pluck(:id, *SMOKING_COLUMNS).filter_map do |id, *values|
      id if self.class.smoking_keys(SMOKING_COLUMNS.zip(values).to_h).include?(key(facet))
    end
    base.where(id: ids)
  end

  def heading(context, facet)
    facet.fetch("kind") == "genre" ? "#{context}で喫煙できる#{facet.fetch('label')}" : "#{context}の#{facet.fetch('label')}の店"
  end

  def published(entry)
    definitions.select { |facet| decision(entry, facet).fetch(:published) }
  end

  def all_published
    parents.flat_map { |entry| published(entry).map { |facet| [entry, facet] } }
  end

  def decision(entry, facet)
    decisions.fetch(path(entry, facet)) do
      { published: false, canonical: path(entry, facet), reason: stats(entry, facet).fetch("count").zero? ? "no_shops" : "insufficient_shops" }
    end
  end

  private

  def parents
    @parents ||= %w[region station].flat_map { |kind| @directory.published(kind) }
  end

  def fingerprint(ids) = Digest::SHA256.hexdigest(ids.sort.join(","))

  def decisions
    @decisions ||= begin
      seen = {}
      parents.each { |entry| seen[fingerprint(@directory.stats(entry).fetch("ids"))] ||= @directory.path(entry) }
      result = {}
      parents.each do |entry|
        parent_count = @directory.stats(entry).fetch("count")
        definitions.each do |facet|
          candidate_path = path(entry, facet)
          data = stats(entry, facet)
          count = data.fetch("count")
          canonical = candidate_path
          published = count >= GeographicDirectory::MIN_SHOPS
          reason = published ? "eligible" : (count.zero? ? "no_shops" : "insufficient_shops")
          if published && (parent_count - count < MIN_DIFFERENCE || count.fdiv(parent_count) > MAX_PARENT_SHARE)
            published = false
            canonical = @directory.path(entry)
            reason = "near_parent"
          elsif published
            signature = fingerprint(data.fetch("ids"))
            if seen.key?(signature)
              published = false
              canonical = seen.fetch(signature)
              reason = "duplicate"
            else
              seen[signature] = candidate_path
            end
          end
          result[candidate_path] = { published: published, canonical: canonical, reason: reason }
        end
      end
      result
    end
  end
end
