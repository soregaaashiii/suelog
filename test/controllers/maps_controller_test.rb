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

    get map_url

    assert_response :success
    assert_includes response.body, "/shops/#{shop.id}/track_click?kind=phone_click\\u0026target_url=tel%3A0611112222"
    assert_includes response.body, "/shops/#{shop.id}/track_click?kind=affiliate_click\\u0026target_url=https%3A%2F%2Fexample.com%2Ftabelog"
    assert_includes response.body, "食べログで見る"
    assert_includes response.body, "map_click"
  end
end
