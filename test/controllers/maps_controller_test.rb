require "test_helper"

class MapsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get map_url
    assert_response :success
  end

  test "affiliate clicks target path renders map page with conversion seo" do
    get map_affiliate_clicks_url

    assert_response :success
    assert_select "title", text: "大阪で喫煙できる店を地図検索｜電話・ルート・空席確認【吸えログ】"
    assert_select "meta[name='description'][content*='電話・ルート・食べログ']"
    assert_select "link[rel='canonical'][href='#{map_url}']"
    assert_select "h1", text: "大阪で喫煙できる店を地図から探す"
  end

  test "map payload includes phone map and booking click paths" do
    shop = Shop.create!(
      name: "喫煙カフェ テスト",
      address: "大阪府大阪市北区梅田1-1-1",
      area: "梅田",
      nearest_station: "梅田",
      genre: "カフェ",
      smoking_area: :all_smoking,
      smoking_type: :both_ok,
      last_confirmed_on: Date.current,
      approved: true,
      phone: "06-1111-2222",
      latitude: 34.7025,
      longitude: 135.4959,
      tabelog_url: "https://example.com/tabelog"
    )

    get map_url(format: :json), params: { south: 34.70, west: 135.49, north: 34.71, east: 135.50 }
    assert_response :success
    payload = response.parsed_body.fetch("shops").find { |entry| entry["id"] == shop.id }
    assert_includes payload.fetch("phone_url"), "kind=phone_click"
    assert_includes payload.fetch("booking_url"), "kind=affiliate_click"
    assert_equal "食べログで見る", payload["booking_label"]
    assert_includes payload.fetch("map_url"), "kind=map_click"

  end
  test "HTML defers shop data and JSON requires a valid bounded viewport" do
    get map_url
    assert_response :success
    assert_includes response.body, "let allShops = [];"
    get map_url(format: :json)
    assert_response :unprocessable_entity
    get map_url(format: :json), params: { south: "NaN", west: 135, north: 35, east: 136 }
    assert_response :unprocessable_entity
  end

  test "bounds and filters exclude other shops and retain custom genres" do
    shop = Shop.create!(name: "範囲内カフェ", address: "大阪市", genre: "その他", genre_other: "レコードバー・ダーツバー", smoking_area: :all_smoking, smoking_type: :both_ok, last_confirmed_on: Date.current, approved: true, latitude: 34.705, longitude: 135.495)
    bounds = { south: 34.70, west: 135.49, north: 34.71, east: 135.50 }
    get map_url(format: :json), params: bounds.merge(genre: "ダーツバー", smoking_area: "all_smoking")
    assert_equal [shop.id], response.parsed_body["shops"].map { |entry| entry["id"] }
    get map_url(format: :json), params: bounds.merge(genre: "カフェ")
    assert_equal 0, response.parsed_body["total"]
    get map_url(format: :json), params: bounds.merge(west: 135.51, east: 135.52)
    refute_includes response.parsed_body["shops"].map { |entry| entry["id"] }, shop.id
    get map_url(format: :json), params: bounds.merge(open_now_only: "1")
    assert response.parsed_body["shops"].all? { |entry| entry["open_now"] }
  end

  test "wide views return bounded clusters without silently dropping shops" do
    rows = 351.times.map { |i| { name: "集約#{i}", address: "大阪市", approved: true, latitude: 34.704, longitude: 135.494, last_confirmed_on: Date.current, created_at: Time.current, updated_at: Time.current } }
    Shop.insert_all!(rows)
    get map_url(format: :json), params: { south: 34.70, west: 135.49, north: 34.71, east: 135.50 }
    assert_response :success
    data = response.parsed_body
    assert_empty data["shops"]
    assert_operator data["clusters"].size, :<=, 81
    assert_equal data["total"], data["clusters"].sum { |cluster| cluster["count"] }
    assert_operator data["total"], :>=, 351
  end

  test "initial radius excludes shops outside 800m even on wide screens" do
    base = { address: "大阪市", genre: "カフェ", last_confirmed_on: Date.current, approved: true, longitude: 135.4959 }
    near = Shop.create!(base.merge(name: "近い店", latitude: 34.704))
    far = Shop.create!(base.merge(name: "円の外の店", latitude: 34.72))
    get map_url(format: :json), params: { south:34.68, west:135.47, north:34.73, east:135.52, center_lat:34.7025, center_lng:135.4959, radius:800 }
    ids = response.parsed_body["shops"].map { |shop| shop["id"] }
    assert_includes ids, near.id
    refute_includes ids, far.id
  end

end
