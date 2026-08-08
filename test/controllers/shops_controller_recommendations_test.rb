require "test_helper"
require "digest"

class ShopsControllerRecommendationsTest < ActiveSupport::TestCase
  IMAGE_PRELOADS = {
    food_photos_attachments: :blob,
    interior_photos_attachments: :blob,
    exterior_photos_attachments: :blob,
    menu_photos_attachments: :blob
  }.freeze

  setup do
    @controller = ShopsController.new
    @sequence = 0
  end

  test "geo recommendations preserve ids order values and rendered cards" do
    origin = insert_shop(
      latitude: 34.6937,
      longitude: 135.5023,
      genre: "バー",
      genre_other: "パブ"
    )

    candidates = [
      { latitude: 34.6940, longitude: 135.5023, genre: "バー", open: true, confirmed: 1.day.ago.to_date },
      { latitude: 34.6942, longitude: 135.5023, genre: "パブ", open: true, confirmed: nil },
      { latitude: 34.6944, longitude: 135.5023, genre: "バー", open: false, confirmed: Date.current },
      { latitude: 34.6946, longitude: 135.5023, genre: "その他", genre_other: "パブ", open: true },
      { latitude: 34.6948, longitude: 135.5023, genre: "バー", open: false },
      { latitude: 34.6950, longitude: 135.5023, genre: "バー", open: true },
      { latitude: 34.6952, longitude: 135.5023, genre: "バー", open: true },
      { latitude: 34.6954, longitude: 135.5023, genre: "別ジャンル", open: true },
      { latitude: 34.7500, longitude: 135.5023, genre: "バー", open: true },
      { latitude: 34.6941, longitude: 135.5023, genre: "バー", open: true, approved: false },
      { latitude: 34.6941, longitude: 135.5023, genre: "バー", open: true, on_hold: true },
      { latitude: 34.6941, longitude: 135.5023, genre: "バー", open: true, smoking_area: "separated" }
    ].map { |attributes| insert_shop(**attributes) }

    candidates.each_with_index { |shop, index| insert_clicks(shop, index % 4) }

    assert_all_recommendations_match(origin, compare_html: true)
  end

  test "recommendations without coordinates preserve legacy scope and order" do
    origin = insert_shop(latitude: nil, longitude: nil, genre: "バー", genre_other: "パブ")

    9.times do |index|
      shop = insert_shop(
        latitude: index.even? ? nil : 34.69 + (index * 0.001),
        longitude: index.even? ? nil : 135.50,
        genre: index == 8 ? "別ジャンル" : "バー",
        open: index.odd?,
        confirmed: index < 4 ? nil : (index + 1).days.ago.to_date,
        created_at: (index + 1).hours.ago
      )
      insert_clicks(shop, index % 3)
    end

    assert_all_recommendations_match(origin)
  end

  test "candidate counts below at and above the six item limit are unchanged" do
    origin = insert_shop(latitude: nil, longitude: nil, genre: "バー")
    created = 7.times.map do |index|
      shop = insert_shop(genre: "バー", open: index.even?)
      insert_clicks(shop, index)
      shop
    end

    assert_all_recommendations_match(origin)
    assert_equal 6, optimized(:nearby_shops_for, origin).size
    assert_equal 6, optimized(:same_genre_shops_for, origin).size
    assert_equal 6, optimized(:popular_shops_for, origin).size

    created.first(2).each { |shop| shop.update_columns(approved: false) }
    assert_all_recommendations_match(origin.reload)
    assert_equal 5, optimized(:nearby_shops_for, origin).size

    created.drop(2).each { |shop| shop.update_columns(approved: false) }
    assert_all_recommendations_match(origin.reload)
    assert_empty optimized(:nearby_shops_for, origin)
    assert_empty optimized(:same_genre_shops_for, origin)
    assert_empty optimized(:popular_shops_for, origin)
  end

  test "blank genres keep the existing empty same genre result" do
    origin = insert_shop(latitude: nil, longitude: nil, genre: "その他", genre_other: "")
    origin.update_columns(genre: nil, genre_other: nil)
    insert_shop(genre: "バー")

    assert_equal legacy_same_genre(origin.reload), optimized(:same_genre_shops_for, origin)
    assert_empty optimized(:same_genre_shops_for, origin)
  end

  test "distance boundaries and missing coordinates match legacy behavior" do
    origin = insert_shop(latitude: 34.6937, longitude: 135.5023, genre: "バー")
    latitude_degrees_per_km = 1.0 / 111.195
    inside_shop = insert_shop(
      latitude: origin.latitude + (2.99 * latitude_degrees_per_km),
      longitude: origin.longitude,
      genre: "バー"
    )
    outside_shop = insert_shop(
      latitude: origin.latitude + (3.01 * latitude_degrees_per_km),
      longitude: origin.longitude,
      genre: "バー"
    )
    missing_geo = insert_shop(latitude: nil, longitude: nil, genre: "バー")

    assert_all_recommendations_match(origin)
    nearby_ids = optimized(:nearby_shops_for, origin).map(&:id)
    assert_includes nearby_ids, inside_shop.id
    refute_includes nearby_ids, outside_shop.id
    refute_includes nearby_ids, missing_geo.id
  end

  test "popular ranking preserves zero clicks ties nulls and virtual click counts" do
    origin = insert_shop(latitude: nil, longitude: nil, genre: "バー")
    tie_time = 2.days.ago.change(usec: 0)
    shops = 8.times.map do |index|
      insert_shop(
        genre: "バー",
        confirmed: index < 4 ? nil : 3.days.ago.to_date,
        created_at: index < 2 ? tie_time : (index + 1).hours.ago
      )
    end
    insert_clicks(shops[0], 3)
    insert_clicks(shops[1], 3)
    insert_clicks(shops[2], 1)

    expected = legacy_popular(origin)
    actual = optimized(:popular_shops_for, origin)

    assert_shop_results_equal expected, actual, compare_clicks: true
    assert_equal expected.map { |shop| shop.clicks_count.to_i }, actual.map { |shop| shop.clicks_count.to_i }
  end

  test "ranking queries stay narrow and display hydration is limited to ranked ids" do
    origin = insert_shop(genre: "バー")
    8.times { insert_shop(genre: "バー") }

    sql = capture_sql { optimized(:nearby_shops_for, origin) }
    shop_queries = sql.select { |statement| statement.match?(/FROM [\"`]?shops[\"`]?/i) }

    assert_operator shop_queries.size, :>=, 2
    refute_match(/SELECT [\"`]?shops[\"`]?\.\*/i, shop_queries.first)
    assert_match(/shop_business_hour_windows/i, shop_queries.first)
    refute_match(/opening_hours_json/i, shop_queries.first)
    assert_match(/WHERE .*[\"`]?id[\"`]? IN \(/i, shop_queries.last)
  end

  test "five hundred geocoded candidates preserve nearby and same genre results" do
    origin = insert_shop(latitude: 34.6937, longitude: 135.5023, genre: "バー", genre_other: "パブ")

    500.times do |index|
      insert_shop(
        latitude: origin.latitude + ((index % 200) * 0.00005),
        longitude: origin.longitude + ((index % 11) * 0.00003),
        genre: index.even? ? "バー" : "その他",
        genre_other: index.even? ? nil : "パブ",
        open: (index % 3).nonzero?,
        confirmed: (index % 5).zero? ? nil : (index % 30).days.ago.to_date,
        created_at: Time.current - index.seconds
      )
    end

    assert_shop_results_equal legacy_nearby(origin), optimized(:nearby_shops_for, origin)
    assert_shop_results_equal legacy_same_genre(origin), optimized(:same_genre_shops_for, origin)
  end

  test "popular ranking counts clicks once without grouping wide shop rows" do
    origin = insert_shop(latitude: nil, longitude: nil, genre: "バー")
    7.times do |index|
      shop = insert_shop(latitude: nil, longitude: nil, genre: "バー")
      insert_clicks(shop, index)
    end

    sql = capture_sql { optimized(:popular_shops_for, origin) }
    ranking_sql = sql.find do |statement|
      statement.include?("SELECT COUNT(*) FROM shop_clicks") && statement.include?("AS clicks_count")
    end
    display_sql = sql.find do |statement|
      statement.include?("CASE shops.id") && statement.include?("AS clicks_count")
    end

    assert ranking_sql
    assert display_sql
    refute_includes ranking_sql.split(/\sFROM\s/i, 2).first, "shops.*"
    refute_includes ranking_sql, "GROUP BY"
    refute_includes ranking_sql, "active_storage"
    assert_equal 1, ranking_sql.scan("SELECT COUNT(*) FROM shop_clicks").size
    refute_includes display_sql, "shop_clicks"
    assert_match(/WHERE .*[\"`]?id[\"`]? IN \(/i, display_sql)
  end

  private

  def optimized(method, shop)
    @controller.send(method, shop)
  end

  def assert_all_recommendations_match(origin, compare_html: false)
    [
      [ :nearby_shops_for, method(:legacy_nearby), false ],
      [ :same_genre_shops_for, method(:legacy_same_genre), false ],
      [ :popular_shops_for, method(:legacy_popular), true ]
    ].each do |method_name, legacy_method, compare_clicks|
      expected = legacy_method.call(origin)
      actual = optimized(method_name, origin)
      assert_shop_results_equal(expected, actual, compare_clicks: compare_clicks)

      next unless compare_html

      expected_html = render_cards(expected)
      actual_html = render_cards(actual)
      assert_equal Digest::SHA256.hexdigest(expected_html), Digest::SHA256.hexdigest(actual_html)
      assert_equal expected_html, actual_html
    end
  end

  def assert_shop_results_equal(expected, actual, compare_clicks: false)
    assert_equal expected.map(&:id), actual.map(&:id)
    assert_equal expected.size, actual.size

    expected.zip(actual).each do |old_shop, new_shop|
      if old_shop.respond_to?(:distance) || new_shop.respond_to?(:distance)
        assert_in_delta old_shop.distance.to_f, new_shop.distance.to_f, 1e-12
      end
      if old_shop.respond_to?(:bearing) || new_shop.respond_to?(:bearing)
        assert_in_delta old_shop.bearing.to_f, new_shop.bearing.to_f, 1e-12
      end
      assert_equal old_shop.clicks_count.to_i, new_shop.clicks_count.to_i if compare_clicks
    end
  end

  def render_cards(shops)
    ApplicationController.render(
      partial: "shared/shop_cards",
      locals: { shops: shops }
    )
  end

  def legacy_nearby(shop)
    scope = legacy_base_scope(shop)
    nearby = if shop.latitude.present? && shop.longitude.present?
      scope.where.not(latitude: nil, longitude: nil)
           .near([ shop.latitude, shop.longitude ], 3.0, units: :km)
    else
      scope
    end

    legacy_rank(nearby)
  end

  def legacy_same_genre(shop)
    genre_value = shop.genre.to_s.strip
    genre_other_value = shop.genre_other.to_s.strip
    return [] if genre_value.blank? && genre_other_value.blank?

    conditions = []
    bindings = {}
    if genre_value.present?
      conditions << "shops.genre = :genre_value"
      bindings[:genre_value] = genre_value
    end
    if genre_other_value.present?
      conditions << "shops.genre_other = :genre_other_value"
      bindings[:genre_other_value] = genre_other_value
    end

    scope = legacy_base_scope(shop).where(conditions.join(" OR "), bindings)
    if shop.latitude.present? && shop.longitude.present?
      scope = scope.where.not(latitude: nil, longitude: nil)
                   .near([ shop.latitude, shop.longitude ], 5.0, units: :km)
    end

    legacy_rank(scope)
  end

  def legacy_popular(shop)
    scope = Shop.approved
                .where.not(id: shop.id)
                .left_joins(:shop_clicks)
                .preload(IMAGE_PRELOADS)
                .select("shops.*", "COUNT(shop_clicks.id) AS clicks_count")
                .group("shops.id")

    if shop.latitude.present? && shop.longitude.present?
      scope = scope.where.not(latitude: nil, longitude: nil)
                   .near([ shop.latitude, shop.longitude ], 5.0, units: :km)
    end

    scope.order(Arel.sql(<<~SQL.squish)).limit(6).to_a
      COUNT(shop_clicks.id) DESC,
      CASE WHEN shops.last_confirmed_on IS NOT NULL THEN 0 ELSE 1 END ASC,
      shops.last_confirmed_on DESC,
      shops.created_at DESC
    SQL
  end

  def legacy_base_scope(shop)
    scope = Shop.approved.where.not(id: shop.id).preload(IMAGE_PRELOADS)
    if shop.smoking_area.present? && shop.smoking_area != "unknown"
      scope = scope.where(smoking_area: shop.smoking_area)
    end
    scope
  end

  def legacy_rank(scope)
    scope.to_a.sort_by do |candidate|
      [
        candidate.open_now? ? 0 : 1,
        candidate.last_confirmed_on.present? ? 0 : 1,
        - (candidate.last_confirmed_on.to_i rescue 0),
        - candidate.created_at.to_i
      ]
    end.first(6)
  end

  def insert_shop(
    latitude: 34.6937,
    longitude: 135.5023,
    genre: "バー",
    genre_other: nil,
    open: false,
    confirmed: Date.current,
    approved: true,
    on_hold: false,
    smoking_area: "all_smoking",
    created_at: Time.current
  )
    @sequence += 1
    now = Time.current
    hours = open ? all_day_hours : closed_hours
    attributes = {
      name: "Recommendation test #{@sequence}",
      address: "Test address #{@sequence}",
      nearest_station: "Test station",
      approved: approved,
      on_hold: on_hold,
      rejected: false,
      smoking_area: Shop.smoking_areas.fetch(smoking_area),
      smoking_type: Shop.smoking_types.fetch("both_ok"),
      genre: genre,
      genre_other: genre_other,
      last_confirmed_on: confirmed,
      latitude: latitude,
      longitude: longitude,
      opening_hours_json: hours,
      opening_hours_text: nil,
      holiday_hours_text: nil,
      created_at: created_at,
      updated_at: now
    }

    result = Shop.insert_all!([ attributes ], returning: %w[id])
    shop = Shop.find(result.rows.first.first)
    ShopBusinessHoursProjection.sync!(shop)
    shop
  end

  def insert_clicks(shop, count)
    return if count.zero?

    now = Time.current
    rows = count.times.map do
      { shop_id: shop.id, kind: "map_click", created_at: now, updated_at: now }
    end
    ShopClick.insert_all!(rows)
  end

  def all_day_hours
    weekday_hours(closed: false)
  end

  def closed_hours
    weekday_hours(closed: true)
  end

  def weekday_hours(closed:)
    %w[monday tuesday wednesday thursday friday saturday sunday].to_h do |day|
      [ day, closed ? { "closed" => true } : { "open" => "00:00", "close" => "23:59" } ]
    end
  end

  def capture_sql
    statements = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:name] == "SCHEMA" || payload[:cached]

      statements << payload[:sql]
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
    statements
  end
end

class ShopsControllerRecommendationsIntegrationTest < ActionDispatch::IntegrationTest
  test "public shop detail keeps recommendations and SEO markup" do
    now = Time.current
    shop_ids = 7.times.map do |index|
      attributes = {
        name: "Public detail test #{index}",
        address: "Test address #{index}",
        approved: true,
        on_hold: false,
        rejected: false,
        smoking_area: Shop.smoking_areas.fetch("all_smoking"),
        smoking_type: Shop.smoking_types.fetch("both_ok"),
        genre: "バー",
        last_confirmed_on: Date.current,
        latitude: 34.6937 + (index * 0.0001),
        longitude: 135.5023,
        opening_hours_json: {},
        created_at: now - index.minutes,
        updated_at: now
      }
      Shop.insert_all!([ attributes ], returning: %w[id]).rows.first.first
    end

    get shop_url(shop_ids.first)

    assert_response :success
    assert_includes response.body, "この店が合わなければ、近くの候補もチェック"
    assert_includes response.body, "同じジャンルの喫煙できるお店"
    assert_includes response.body, "よく見られている喫煙可のお店"
    assert_select "link[rel='canonical']", count: 1
    assert_select "script[type='application/ld+json']", minimum: 1
  end
end
