require "test_helper"

class GeographiesControllerTest < ActionDispatch::IntegrationTest
  UA = { "User-Agent" => "Mozilla/5.0 Chrome/138.0 Safari/537.36" }.freeze

  setup do
    Shop.update_all(approved: false, on_hold: false)
    Article.update_all(published: false)
    Rails.cache.clear
  end

  test "eligible region and station pages contain distinct metadata and bounded listings" do
    seed_shops(11)
    seed_shops(1, address: "大阪府豊中市庄内1-1", nearest_station: "庄内駅から100m", prefix: "別地域")
    get "/areas/suita", headers: UA
    assert_response :success
    assert_select "h1", text: "吹田市で喫煙できる店"
    assert_select "link[rel='canonical'][href='https://suelog.jp/areas/suita']"
    assert_select "meta[name='robots'][content='index,follow']"
    assert_select ".result-hit-text", text: "11件ヒット"
    assert_select ".shop-card__titleLink", text: /別地域/, count: 0
    assert_select "a[href='/stations/esaka']"
    assert_select ".geo-context", text: /居酒屋 11件/
    schema = Nokogiri::HTML(response.body).at_css('script[type="application/ld+json"]')
    assert_equal "BreadcrumbList", JSON.parse(schema.text).fetch("@type")
    get "/stations/esaka", headers: UA
    assert_response :success
    assert_select "h1", text: "江坂駅周辺で喫煙できる店"
    assert_select "link[rel='canonical'][href='https://suelog.jp/stations/esaka']"
    assert_select ".geo-context a[href='/areas/suita']"
    assert_select ".result-hit-text", text: "11件ヒット"
  end

  test "hub and sitemap link only to eligible pages and legacy URLs stay intact" do
    seed_shops(10)
    seed_shops(2, address: "大阪府豊中市庄内1-1", nearest_station: "庄内駅から100m", prefix: "少数")
    get "/areas", headers: UA
    assert_response :success
    assert_select "a[href='/areas/suita']"
    assert_select "a[href='/stations/esaka']"
    assert_select "a[href='/areas/toyonaka']", count: 0
    assert_select "a[href='/umeda']"
    get "/sitemaps/pages.xml"
    assert_response :success
    assert_includes response.body, "https://suelog.jp/stations/esaka"
    assert_not_includes response.body, "https://suelog.jp/stations/shonai"
    get "/umeda", headers: UA
    assert_response :success
    assert_select "link[rel='canonical'][href='http://www.example.com/umeda']"
  end

  test "thin pages are noindex and empty or unknown locations are not found" do
    seed_shops(2)
    get "/stations/esaka", headers: UA
    assert_response :success
    assert_select "meta[name='robots'][content='noindex,follow']"
    get "/areas/does-not-exist", headers: UA
    assert_response :not_found
    get "/stations/kyobashi", headers: UA
    assert_response :not_found
  end

  test "shop detail links back to eligible region and station pages" do
    seed_shops(10)
    shop = Shop.find_by!(name: "江坂0")
    get "/shops/#{shop.id}", headers: UA
    assert_response :success
    assert_select ".shop-show__relatedLinks a[href='/areas/suita']", text: "吹田市の店舗一覧"
    assert_select ".shop-show__relatedLinks a[href='/stations/esaka']", text: "江坂駅の店舗一覧"
  end

  test "filters and pagination retain the geographic scope and do not create indexable filter URLs" do
    seed_shops(31)
    get "/stations/esaka?page=2", headers: UA
    assert_response :success
    assert_select ".shop-card__titleLink", count: 1
    assert_select "meta[name='robots'][content='noindex,follow']"
    assert_select "form[action='/stations/esaka']"
    get "/areas/suita", params: { genre: "カフェ" }, headers: UA
    assert_response :success
    assert_select ".result-hit-text", text: "0件ヒット"
    assert_select "meta[name='robots'][content='noindex,follow']"
    get "/areas/suita?open_now_only=1", headers: UA
    assert_select "meta[name='robots'][content='noindex,follow']"
  end

  private

  def seed_shops(count, **overrides)
    prefix = overrides.delete(:prefix) || "江坂"
    now = Time.current
    Shop.insert_all!(Array.new(count) do |i|
      { name: "#{prefix}#{i}", address: "大阪府吹田市江坂町1-#{i}", nearest_station: "江坂駅から#{i + 100}m",
        genre: "居酒屋", approved: true, on_hold: false, rejected: false, smoking_area: 1, smoking_type: 0,
        last_confirmed_on: Date.current, created_at: now, updated_at: now }.merge(overrides)
    end)
  end
end
