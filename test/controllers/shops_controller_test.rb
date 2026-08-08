require "test_helper"

class ShopsControllerTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  test "should get index" do
    get shops_index_url
    assert_response :success
  end

  test "popular shops preserve the legacy ranking and display values" do
    current = insert_shop(name: "Current", created_at: Time.zone.parse("2025-01-01 00:00:00"))
    popular = insert_shop(name: "Popular", confirmed_on: Date.new(2025, 1, 8), created_at: Time.zone.parse("2025-01-08 00:00:00"))
    tied_newer = insert_shop(name: "Tied newer", confirmed_on: Date.new(2025, 1, 7), created_at: Time.zone.parse("2025-01-07 00:00:00"))
    tied_older = insert_shop(name: "Tied older", confirmed_on: Date.new(2025, 1, 6), created_at: Time.zone.parse("2025-01-06 00:00:00"))
    zero_newer = insert_shop(name: "Zero newer", confirmed_on: Date.new(2025, 1, 5), created_at: Time.zone.parse("2025-01-05 00:00:00"))
    zero_older = insert_shop(name: "Zero older", confirmed_on: Date.new(2025, 1, 4), created_at: Time.zone.parse("2025-01-04 00:00:00"))
    null_confirmed = insert_shop(name: "Null confirmed", confirmed_on: nil, created_at: Time.zone.parse("2025-01-09 00:00:00"))
    seventh = insert_shop(name: "Seventh", confirmed_on: nil, created_at: Time.zone.parse("2025-01-03 00:00:00"))
    hidden = insert_shop(name: "Hidden", approved: false, created_at: Time.zone.parse("2025-01-10 00:00:00"))
    held = insert_shop(name: "Held", on_hold: true, created_at: Time.zone.parse("2025-01-11 00:00:00"))

    insert_clicks(current, 20)
    insert_clicks(popular, 5)
    insert_clicks(tied_newer, 3)
    insert_clicks(tied_older, 3)
    insert_clicks(hidden, 30)
    insert_clicks(held, 30)

    expected = legacy_popular_shops_for(current)
    actual = popular_shops_for(current)

    assert_equal [ popular.id, tied_newer.id, tied_older.id, zero_newer.id, zero_older.id, null_confirmed.id ], actual.map(&:id)
    assert_popular_results_equal expected, actual
    assert_not_includes actual.map(&:id), current.id
    assert_not_includes actual.map(&:id), hidden.id
    assert_not_includes actual.map(&:id), held.id
    assert_not_includes actual.map(&:id), seventh.id
  end

  test "popular shops preserve geocoder scope distance ordering and six item limit" do
    current = insert_shop(name: "Geo current", latitude: 34.6937, longitude: 135.5023)
    nearby = insert_shop(name: "Nearby", latitude: 34.6940, longitude: 135.5023, area: "Different area", station: "Different station", genre: "バー")
    farther_popular = insert_shop(name: "Farther popular", latitude: 34.7000, longitude: 135.5023, area: "Same area", station: "Same station", genre: "居酒屋")
    remaining = 5.times.map do |index|
      insert_shop(
        name: "Geo #{index}",
        latitude: 34.7010 + (index * 0.001),
        longitude: 135.5023,
        created_at: Time.zone.parse("2025-01-#{format('%02d', index + 1)} 00:00:00")
      )
    end
    outside = insert_shop(name: "Outside radius", latitude: 35.0, longitude: 135.5023)

    insert_clicks(farther_popular, 50)
    insert_clicks(outside, 100)

    expected = legacy_popular_shops_for(current)
    actual = popular_shops_for(current)

    assert_equal 6, actual.size
    assert_equal nearby.id, actual.first.id
    assert_not_includes actual.map(&:id), outside.id
    assert_popular_results_equal expected, actual, compare_distance: true
    assert actual.all? { |shop| shop.respond_to?(:distance) }
    assert_equal remaining.first(4).map(&:id).sort, (actual.map(&:id) & remaining.map(&:id)).sort
  end

  test "popular shops count every click timestamp and preserve short result sets" do
    current = insert_shop(name: "Period current")
    candidate = insert_shop(name: "All-time clicks")
    no_clicks = insert_shop(name: "No clicks", confirmed_on: nil)
    old_time = Time.zone.parse("2010-01-01 00:00:00")
    future_time = Time.zone.parse("2035-01-01 00:00:00")
    insert_clicks(candidate, 1, created_at: old_time)
    insert_clicks(candidate, 1, created_at: future_time)

    expected = legacy_popular_shops_for(current)
    actual = popular_shops_for(current)

    assert_equal [ candidate.id, no_clicks.id ], actual.map(&:id)
    assert_equal 2, actual.first.clicks_count.to_i
    assert_equal 0, actual.last.clicks_count.to_i
    assert_popular_results_equal expected, actual
  end

  test "popular shops preserve the legacy order for exact ties" do
    current = insert_shop(name: "Tie current")
    timestamp = Time.zone.parse("2025-01-01 00:00:00")
    7.times do |index|
      shop = insert_shop(name: "Exact tie #{index}", confirmed_on: nil, created_at: timestamp)
      insert_clicks(shop, 1)
    end

    expected = legacy_popular_shops_for(current)
    actual = popular_shops_for(current)

    assert_equal 6, actual.size
    assert_popular_results_equal expected, actual
  end

  test "popular shop cards render identically to the legacy results" do
    travel_to Time.zone.parse("2025-01-10 12:00:00") do
      current = insert_shop(name: "HTML current")
      7.times do |index|
        shop = insert_shop(
          name: "HTML candidate #{index}",
          confirmed_on: Date.new(2025, 1, index + 1),
          created_at: Time.zone.parse("2025-01-#{format('%02d', index + 1)} 00:00:00")
        )
        insert_clicks(shop, 7 - index)
      end

      expected_html = render_shop_cards(legacy_popular_shops_for(current))
      actual_html = render_shop_cards(popular_shops_for(current))

      assert_equal Digest::SHA256.hexdigest(expected_html), Digest::SHA256.hexdigest(actual_html)
      assert_equal expected_html, actual_html
    end
  end

  test "optimized popular ranking groups only narrow columns before loading six shops" do
    current = insert_shop(name: "SQL current")
    7.times do |index|
      shop = insert_shop(name: "SQL candidate #{index}")
      insert_clicks(shop, index)
    end

    sql_statements = []
    subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
      sql_statements << payload[:sql] unless payload[:name] == "SCHEMA"
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      popular_shops_for(current)
    end

    ranking_sql = sql_statements.find do |sql|
      sql.include?("COUNT(shop_clicks.id)") && sql.include?("GROUP BY")
    end
    display_sql = sql_statements.find do |sql|
      sql.include?("CASE shops.id") && sql.include?("AS clicks_count")
    end

    assert ranking_sql
    assert display_sql
    assert_match(/SELECT\s+"?shops"?\."?id"?,\s*COUNT\(shop_clicks\.id\)/i, ranking_sql)
    assert_not_includes ranking_sql.split(/\sFROM\s/i, 2).first, "shops.*"
    assert_not_includes ranking_sql, "active_storage"
    assert_not_includes display_sql, "shop_clicks"
    assert_match(/WHERE .*shops.*id.* IN/i, display_sql)
  end

  private

  def popular_shops_for(shop)
    ShopsController.new.send(:optimized_popular_shops_for, shop)
  end

  def legacy_popular_shops_for(shop)
    scope = Shop.approved
                .where.not(id: shop.id)
                .left_joins(:shop_clicks)
                .includes(
                  food_photos_attachments: :blob,
                  interior_photos_attachments: :blob,
                  exterior_photos_attachments: :blob,
                  menu_photos_attachments: :blob
                )
                .select("shops.*", "COUNT(shop_clicks.id) AS clicks_count")
                .group("shops.id")

    if shop.latitude.present? && shop.longitude.present?
      scope = scope.where.not(latitude: nil, longitude: nil)
                   .near([ shop.latitude, shop.longitude ], 5.0, units: :km)
    end

    scope
      .order(Arel.sql(<<~SQL.squish))
        COUNT(shop_clicks.id) DESC,
        CASE WHEN shops.last_confirmed_on IS NOT NULL THEN 0 ELSE 1 END ASC,
        shops.last_confirmed_on DESC,
        shops.created_at DESC
      SQL
      .limit(6)
      .to_a
  end

  def insert_shop(name:, approved: true, on_hold: false, confirmed_on: Date.new(2025, 1, 1),
                  created_at: Time.zone.parse("2025-01-01 00:00:00"), latitude: nil, longitude: nil,
                  area: "Test area", station: "Test station", genre: "居酒屋")
    Shop.insert_all!([ {
      name:,
      address: "#{name} address",
      area:,
      nearest_station: station,
      genre:,
      approved:,
      on_hold:,
      last_confirmed_on: confirmed_on,
      smoking_area: Shop.smoking_areas.fetch("separated"),
      smoking_type: Shop.smoking_types.fetch("both_ok"),
      latitude:,
      longitude:,
      created_at:,
      updated_at: created_at
    } ])
    Shop.find_by!(name:)
  end

  def insert_clicks(shop, count, created_at: Time.zone.parse("2025-01-01 00:00:00"))
    return if count.zero?

    ShopClick.insert_all!(Array.new(count) do
      {
        shop_id: shop.id,
        kind: "phone_click",
        created_at:,
        updated_at: created_at
      }
    end)
  end

  def assert_popular_results_equal(expected, actual, compare_distance: false)
    assert_equal expected.map(&:id), actual.map(&:id)
    assert_equal expected.map { |shop| shop.clicks_count.to_i }, actual.map { |shop| shop.clicks_count.to_i }
    return unless compare_distance

    assert_equal expected.map { |shop| shop.distance.to_f }, actual.map { |shop| shop.distance.to_f }
  end

  def render_shop_cards(shops)
    ApplicationController.render(
      partial: "shared/shop_cards",
      locals: { shops: }
    )
  end
end
