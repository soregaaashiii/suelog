# frozen_string_literal: true

class GeographicDirectory
  include Rails.application.routes.url_helpers

  CONFIG_TEXT = Rails.root.join("config/seo/geographies.json").read.freeze
  CONFIG = JSON.parse(CONFIG_TEXT).freeze
  MIN_SHOPS = 10 # Editorial publication threshold, not a search-engine requirement.
  CACHE_KEY = "geographic-directory/v1/#{Digest::SHA256.hexdigest(CONFIG_TEXT)}"
  ADDRESS_SQL = "REPLACE(REPLACE(COALESCE(shops.address, ''), ' ', ''), '　', '')".freeze

  def regions = CONFIG.fetch("regions")
  def stations = CONFIG.fetch("stations")

  def definition(kind, slug)
    config = (kind == "region" ? regions : stations)[slug]
    config&.merge("kind" => kind, "slug" => slug)
  end

  def path(entry)
    entry.fetch("kind") == "region" ? geographic_region_path(entry.fetch("slug")) : geographic_station_path(entry.fetch("slug"))
  end

  def statistics
    @statistics ||= Rails.cache.fetch(CACHE_KEY, expires_in: 5.minutes) { build_statistics }
  end

  def stats(entry)
    statistics.fetch(entry.fetch("kind")).fetch(entry.fetch("slug"))
  end

  def published?(entry) = stats(entry).fetch("count") >= MIN_SHOPS

  def published(kind)
    config = kind == "region" ? regions : stations
    config.keys.map { |slug| definition(kind, slug) }.select { |entry| published?(entry) }
      .sort_by { |entry| [-stats(entry).fetch("count"), entry.fetch("slug")] }
  end

  def region_key(address)
    value = address.to_s.delete(" 　").delete_prefix("大阪府")
    # Prefix matching is safe here: all definitions end at a city or ward boundary.
    regions.find { |_slug, config| value.start_with?(config.fetch("label")) }&.first
  end

  def station_key(raw, region)
    return if region.nil?

    text = raw.to_s.unicode_normalize(:nfkc).strip
    # Use the final distance-to-station statement, not every station mentioned in access directions.
    aliases_by_region.fetch(region, []).find do |name, _slug, pattern|
      text == name || text.match?(pattern)
    end&.fetch(1)
  end

  def scope(entry)
    keys = entry.fetch("kind") == "region" ? [entry.fetch("slug")] : entry.fetch("regions")
    conditions = keys.map { "(#{ADDRESS_SQL} LIKE ? OR #{ADDRESS_SQL} LIKE ?)" }
    bindings = keys.flat_map do |key|
      label = ActiveRecord::Base.sanitize_sql_like(regions.fetch(key).fetch("label"))
      ["大阪府#{label}%", "#{label}%"]
    end
    relation = Shop.approved.where(conditions.join(" OR "), *bindings)
    entry.fetch("kind") == "station" ? relation.where(id: stats(entry).fetch("ids")) : relation
  end

  def related(entry)
    if entry.fetch("kind") == "region"
      published("station").select { |station| station.fetch("regions").include?(entry.fetch("slug")) }
    else
      entry.fetch("regions").map { |key| definition("region", key) }.select { |region| published?(region) }
    end
  end

  def links_for(shop)
    region = region_key(shop.address)
    return [] unless region

    station = station_key(shop.nearest_station, region)
    [definition("region", region), station && definition("station", station)].compact
      .select { |entry| published?(entry) }
  end

  private

  def aliases_by_region
    @aliases_by_region ||= begin
      result = Hash.new { |hash, key| hash[key] = [] }
      stations.each do |slug, config|
        config.fetch("aliases").uniq.each do |name|
          pattern = /(?:\A|[\s「」『』。・\/]|(?:徒歩|歩いて)?\d+分)#{Regexp.escape(name)}(?:\([^)]*\))?から[\d,]+m\z/
          config.fetch("regions").each { |region| result[region] << [name, slug, pattern] }
        end
      end
      result.transform_values { |values| values.sort_by { |name, _slug, _pattern| -name.length } }
    end
  end

  def build_statistics
    result = { "region" => {}, "station" => {} }
    { "region" => regions, "station" => stations }.each do |kind, entries|
      entries.each_key { |slug| result[kind][slug] = { "count" => 0, "genres" => {}, "ids" => [] } }
    end
    # Scalar fields only; no shop objects, photos, reviews, or per-region database queries.
    Shop.approved.pluck(:id, :address, :nearest_station, :genre).each do |id, address, raw_station, genre|
      region = region_key(address)
      next unless region

      station = station_key(raw_station, region)
      [["region", region], ["station", station]].each do |kind, slug|
        next unless slug
        data = result[kind][slug]
        data["count"] += 1
        data["ids"] << id if kind == "station"
        genre.to_s.split(/[、,，\/／\s]+/).reject { |name| name.blank? || name == "その他" }.uniq.each do |name|
          data["genres"][name] = data["genres"].fetch(name, 0) + 1
        end
      end
    end
    result
  end
end
