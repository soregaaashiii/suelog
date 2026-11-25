# frozen_string_literal: true

# The admin inventory uses exactly the same snapshot and publication decisions
# as navigation and sitemaps; it never probes every URL or loads shop objects.
class SeoPageCatalog
  HOST = PublicSitemap::HOST
  KINDS = { "region" => "地域", "station" => "駅", "genre" => "ジャンル別", "smoking" => "喫煙条件別" }.freeze
  STATUSES = { "index" => "index対象", "noindex" => "noindex", "not_found" => "404対象" }.freeze
  REASONS = {
    "eligible" => "掲載基準を満たす",
    "no_shops" => "掲載店舗なし",
    "insufficient_shops" => "店舗数が基準未満",
    "near_parent" => "親ページとの差が小さい",
    "duplicate" => "同じ店舗集合のページあり"
  }.freeze
  REASON_DETAILS = {
    "eligible" => "内部リンク・サイトマップへの掲載対象です。",
    "no_shops" => "掲載店舗が0件のため、ページは404になります。",
    "insufficient_shops" => "掲載店舗が#{GeographicDirectory::MIN_SHOPS}件未満のため、内部リンク・サイトマップの対象外です。",
    "near_parent" => "親ページとの差が#{GeographicFacets::MIN_DIFFERENCE}店舗未満、または親の#{(GeographicFacets::MAX_PARENT_SHARE * 100).to_i}%を超える店舗が重なるため、親ページに統合します。",
    "duplicate" => "同じ店舗集合のページがあるため、canonicalに表示したURLに統合します。"
  }.freeze

  def initialize(directory = GeographicDirectory.new)
    @directory = directory
    @facets = GeographicFacets.new(directory)
  end

  def rows
    @rows ||= %w[region station].flat_map do |kind|
      config = kind == "region" ? @directory.regions : @directory.stations
      config.keys.flat_map do |slug|
        entry = @directory.definition(kind, slug)
        count = @directory.stats(entry).fetch("count")
        parent = row(entry, nil, count, @directory.path(entry),
          published: @directory.published?(entry), canonical: @directory.path(entry),
          reason: count.zero? ? "no_shops" : (@directory.published?(entry) ? "eligible" : "insufficient_shops"))
        [parent] + @facets.definitions.map do |facet|
          row(entry, facet, @facets.stats(entry, facet).fetch("count"), @facets.path(entry, facet), **@facets.decision(entry, facet))
        end
      end
    end
  end

  def counts
    @counts ||= STATUSES.keys.to_h { |status| [status, rows.count { |row| row[:status] == status }] }.merge("total" => rows.length)
  end

  def search(query: nil, kind: nil, status: nil, reason: nil, sort: nil)
    words = query.to_s.strip.first(100).unicode_normalize(:nfkc).downcase.split
    filtered = rows.select do |row|
      (!KINDS.key?(kind) || row[:kind] == kind) &&
        (!STATUSES.key?(status) || row[:status] == status) &&
        (!REASONS.key?(reason) || row[:reason] == reason) &&
        words.all? { |word| "#{row[:label]} #{row[:url]}".unicode_normalize(:nfkc).downcase.include?(word) }
    end
    filtered.sort_by do |row|
      case sort
      when "shops_asc" then [row[:count], row[:path]]
      when "url" then [row[:path]]
      else [-row[:count], row[:path]]
      end
    end
  end

  private

  def row(entry, facet, count, path, published:, canonical:, reason:)
    {
      label: facet ? "#{entry.fetch('label')} / #{facet.fetch('label')}" : entry.fetch("label"),
      kind: facet ? facet.fetch("kind") : entry.fetch("kind"),
      geography_kind: entry.fetch("kind"), count: count,
      parent_count: @directory.stats(entry).fetch("count"),
      path: path, url: HOST + path, canonical: count.zero? ? nil : HOST + canonical,
      status: count.zero? ? "not_found" : (published ? "index" : "noindex"), reason: reason
    }
  end
end
