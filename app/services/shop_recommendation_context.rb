# frozen_string_literal: true

class ShopRecommendationContext
  IMAGE_PRELOADS = {
    food_photos_attachments: :blob,
    interior_photos_attachments: :blob,
    exterior_photos_attachments: :blob,
    menu_photos_attachments: :blob
  }.freeze

  OPENING_HOUR_ATTRIBUTES = %w[
    id
    opening_hours_json
    holiday_hours_text
    opening_hours_text
  ].freeze

  def initialize(shop)
    @shop = shop
  end

  def nearby
    results.fetch(:nearby)
  end

  def same_genre
    results.fetch(:same_genre)
  end

  def popular
    results.fetch(:popular)
  end

  private

  attr_reader :shop

  def results
    @results ||= build_results
  end

  def build_results
    query_rows = Shop.connection.select_all(recommendation_sql).to_a
    opening_rows, popular_rows = query_rows.partition { |row| row.fetch("result_kind") == "opening" }
    open_by_id = opening_rows.to_h do |row|
      [ row.fetch("id").to_i, opening_hours_shop(row).open_now? ]
    end

    nearby_rows = opening_rows.select { |row| truthy_database_value?(row["nearby_match"]) }
    same_genre_rows = opening_rows.select { |row| truthy_database_value?(row["same_genre_match"]) }
    ranked_rows = {
      nearby: rank_open_rows(nearby_rows, open_by_id),
      same_genre: rank_open_rows(same_genre_rows, open_by_id),
      popular: popular_rows.first(6)
    }

    hydrate(ranked_rows)
  end

  def recommendation_sql
    connection = Shop.connection
    distance_sql = Shop.send(:distance_sql, shop.latitude, shop.longitude, units: :km)
    bearing_sql = Shop.send(:bearing_sql, shop.latitude, shop.longitude, units: :km)
    five_km_bounds = bounding_condition(5.0, table_name: "shops")
    nearby_condition = nearby_distance_condition
    smoking_condition = recommendation_smoking_condition
    genre_condition = recommendation_genre_condition
    exact_radius_condition = if connection.adapter_name.match?(/sqlite/i)
      "1 = 1"
    else
      "distance BETWEEN 0.0 AND 5.0"
    end

    <<~SQL.squish
      WITH distance_candidates AS MATERIALIZED (
        SELECT shops.id,
               shops.genre,
               shops.genre_other,
               shops.smoking_area,
               shops.last_confirmed_on,
               shops.created_at,
               shops.latitude,
               shops.longitude,
               #{distance_sql} AS distance,
               #{bearing_sql} AS bearing
        FROM shops
        WHERE shops.approved = #{connection.quoted_true}
          AND shops.on_hold = #{connection.quoted_false}
          AND shops.id != #{connection.quote(shop.id)}
          AND shops.latitude IS NOT NULL
          AND shops.longitude IS NOT NULL
          AND #{five_km_bounds}
      ), base_candidates AS MATERIALIZED (
        SELECT *
        FROM distance_candidates
        WHERE #{exact_radius_condition}
      ), opening_candidates AS (
        SELECT base_candidates.*,
               shops.opening_hours_json,
               shops.holiday_hours_text,
               shops.opening_hours_text,
               (#{nearby_condition} AND #{smoking_condition}) AS nearby_match,
               (#{genre_condition} AND #{smoking_condition}) AS same_genre_match,
               ROW_NUMBER() OVER (ORDER BY base_candidates.distance ASC) AS result_position
        FROM base_candidates
        INNER JOIN shops ON shops.id = base_candidates.id
        WHERE (#{nearby_condition} AND #{smoking_condition})
           OR (#{genre_condition} AND #{smoking_condition})
      ), popular_scored AS MATERIALIZED (
        SELECT base_candidates.*,
               (SELECT COUNT(*) FROM shop_clicks WHERE shop_clicks.shop_id = base_candidates.id) AS clicks_count
        FROM base_candidates
      ), popular_candidates AS (
        SELECT popular_scored.*,
               ROW_NUMBER() OVER (
                 ORDER BY distance ASC,
                          clicks_count DESC,
                          CASE WHEN last_confirmed_on IS NOT NULL THEN 0 ELSE 1 END ASC,
                          last_confirmed_on DESC,
                          created_at DESC
               ) AS result_position
        FROM popular_scored
        ORDER BY distance ASC,
                 clicks_count DESC,
                 CASE WHEN last_confirmed_on IS NOT NULL THEN 0 ELSE 1 END ASC,
                 last_confirmed_on DESC,
                 created_at DESC
        LIMIT 6
      )
      SELECT 'opening' AS result_kind,
             opening_candidates.id,
             opening_candidates.last_confirmed_on,
             opening_candidates.created_at,
             opening_candidates.distance,
             opening_candidates.bearing,
             opening_candidates.opening_hours_json,
             opening_candidates.holiday_hours_text,
             opening_candidates.opening_hours_text,
             opening_candidates.nearby_match,
             opening_candidates.same_genre_match,
             NULL AS clicks_count,
             opening_candidates.result_position
      FROM opening_candidates
      UNION ALL
      SELECT 'popular' AS result_kind,
             popular_candidates.id,
             popular_candidates.last_confirmed_on,
             popular_candidates.created_at,
             popular_candidates.distance,
             popular_candidates.bearing,
             NULL AS opening_hours_json,
             NULL AS holiday_hours_text,
             NULL AS opening_hours_text,
             #{connection.quoted_false} AS nearby_match,
             #{connection.quoted_false} AS same_genre_match,
             popular_candidates.clicks_count,
             popular_candidates.result_position
      FROM popular_candidates
      ORDER BY result_kind ASC, result_position ASC
      /* shop_recommendations_base_candidates */
    SQL
  end

  def rank_open_rows(rows, open_by_id)
    rows.sort_by do |row|
      [
        open_by_id.fetch(row.fetch("id").to_i) ? 0 : 1,
        row["last_confirmed_on"].present? ? 0 : 1,
        -safe_legacy_date_integer(row["last_confirmed_on"]),
        -time_rank(row.fetch("created_at")).to_i
      ]
    end.first(6)
  end

  def hydrate(ranked_rows)
    selected_rows = ranked_rows.values.flatten
    ids = selected_rows.map { |row| row.fetch("id").to_i }.uniq
    return ranked_rows.transform_values { [] } if ids.empty?

    rows_by_id = selected_rows.index_by { |row| row.fetch("id").to_i }
    shops_by_id = Shop.where(id: ids)
      .annotate("shop_recommendations_display_shops")
      .preload(IMAGE_PRELOADS)
      .index_by(&:id)

    shops_by_id.each do |id, hydrated_shop|
      attach_ranking_values(hydrated_shop, rows_by_id.fetch(id))
    end

    ranked_rows.transform_values do |rows|
      rows.filter_map { |row| shops_by_id[row.fetch("id").to_i] }
    end
  end

  def attach_ranking_values(hydrated_shop, ranking_row)
    distance = ranking_row.fetch("distance")
    bearing = ranking_row.fetch("bearing")
    clicks_count = ranking_row["clicks_count"].to_i

    hydrated_shop.define_singleton_method(:distance) { distance }
    hydrated_shop.define_singleton_method(:bearing) { bearing }
    hydrated_shop.define_singleton_method(:clicks_count) { clicks_count }
  end

  def opening_hours_shop(row)
    Shop.instantiate(row.slice(*OPENING_HOUR_ATTRIBUTES))
  end

  def recommendation_smoking_condition
    return "1 = 1" if shop.smoking_area.blank? || shop.smoking_area == "unknown"

    "base_candidates.smoking_area = #{Shop.connection.quote(Shop.smoking_areas.fetch(shop.smoking_area))}"
  end

  def recommendation_genre_condition
    connection = Shop.connection
    conditions = []
    genre = shop.genre.to_s.strip
    genre_other = shop.genre_other.to_s.strip
    conditions << "base_candidates.genre = #{connection.quote(genre)}" if genre.present?
    conditions << "base_candidates.genre_other = #{connection.quote(genre_other)}" if genre_other.present?
    conditions.any? ? "(#{conditions.join(' OR ')})" : "1 = 0"
  end

  def nearby_distance_condition
    return "base_candidates.distance <= 3.0" unless Shop.connection.adapter_name.match?(/sqlite/i)

    bounding_condition(3.0, table_name: "base_candidates")
  end

  def bounding_condition(radius_km, table_name:)
    bounds = Geocoder::Calculations.bounding_box(
      [ shop.latitude, shop.longitude ],
      radius_km,
      units: :km
    )
    Geocoder::Sql.within_bounding_box(
      *bounds,
      "#{table_name}.latitude",
      "#{table_name}.longitude"
    )
  end

  def truthy_database_value?(value)
    value == true || value.to_s == "1"
  end

  def safe_legacy_date_integer(value)
    value.to_i
  rescue NoMethodError
    0
  end

  def time_rank(value)
    value.respond_to?(:to_time) ? value.to_time : Time.zone.parse(value.to_s)
  end
end
