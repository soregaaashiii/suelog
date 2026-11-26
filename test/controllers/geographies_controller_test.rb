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

  test "genre and smoking facets expose consistent navigation canonical and sitemap entries" do
    seed_shops(10, smoking_unverified: false)
    seed_shops(5, genre: "カフェ", smoking_unverified: false, prefix: "喫茶")
    seed_shops(5, genre: "バー", smoking_area: 0, smoking_unverified: false, prefix: "バー")
    get "/areas/suita/genre/izakaya", headers: UA
    assert_response :success
    assert_select "h1", text: "吹田市で喫煙できる居酒屋"
    assert_select ".result-hit-text", text: "10件ヒット"
    assert_select "meta[name='robots'][content='index,follow']"
    assert_select "link[rel='canonical'][href='https://suelog.jp/areas/suita/genre/izakaya']"
    assert_select ".geo-context a[href='/areas/suita/smoking/seat-smoking']"
    get "/areas/suita/smoking/seat-smoking", headers: UA
    assert_response :success
    assert_select "h1", text: "吹田市の席で喫煙可の店"
    assert_select ".result-hit-text", text: "15件ヒット"
    assert_select ".geo-context", text: /終日・全席での喫煙を保証するものではありません/
    assert_select ".geo-context a[href='/areas/suita/genre/izakaya']"
    get "/sitemaps/geographic-facets.xml"
    assert_response :success
    assert_includes response.body, "https://suelog.jp/areas/suita/genre/izakaya"
    assert_includes response.body, "https://suelog.jp/areas/suita/smoking/seat-smoking"
    assert_not_includes response.body, "/stations/esaka/genre/izakaya"
    get "/sitemap.xml"
    assert_includes response.body, "/sitemaps/geographic-facets.xml"
    get "/stations/esaka/genre/izakaya", headers: UA
    assert_select "meta[name='robots'][content='noindex,follow']"
    assert_select "link[rel='canonical'][href='https://suelog.jp/areas/suita/genre/izakaya']"
    get "/shops/#{Shop.find_by!(name: '江坂0').id}", headers: UA
    assert_select ".shop-show__relatedLinks a[href='/areas/suita/genre/izakaya']"
    assert_select ".shop-show__relatedLinks a[href='/areas/suita/smoking/seat-smoking']"
    get "/areas/suita/genre/izakaya", params: { genre: "カフェ" }, headers: UA
    assert_select ".result-hit-text", text: "0件ヒット"
    assert_select "meta[name='robots'][content='noindex,follow']"
    get "/areas/suita/genre/unknown", headers: UA
    assert_response :not_found
    get "/areas/suita/smoking/heated-only", headers: UA
    assert_response :not_found
  end

  test "guide explains real facet intersections and keeps metadata and publication decisions" do
    seed_shops(12, smoking_unverified: false)
    seed_shops(5, genre: "カフェ", smoking_unverified: false, prefix: "喫茶")
    seed_shops(5, genre: "バー", smoking_area: 0, smoking_unverified: false, prefix: "バー")
    get "/areas/suita/genre/izakaya", headers: UA
    assert_response :success
    assert_select ".geo-guide", text: /掲載22件のうち.*12件/
    assert_select ".geo-guide [data-smoking-condition='seat-smoking']", text: /この一覧内 12件/
    assert_select ".geo-guide [data-smoking-condition='smoking-room']", text: /この一覧内 0件/
    assert_select ".geo-guide a[href='/areas/suita/smoking/seat-smoking']", text: /17件/
    assert_select ".geo-guide a[href*='?']", count: 0
    document = Nokogiri::HTML(response.body)
    assert document.at_css(".geo-guide").previous_element.css(".shop-card__titleLink").any?, "Guide must follow the shop listing"
    assert_select "link[rel='canonical'][href='https://suelog.jp/areas/suita/genre/izakaya']"
    assert_select "meta[name='robots'][content='index,follow']"
    get "/areas/suita", params: { genre: "カフェ" }, headers: UA
    assert_select ".geo-guide", count: 0
    get "/areas/suita?page=2", headers: UA
    assert_select ".geo-guide", count: 0
    get "/stations/esaka/genre/izakaya", headers: UA
    assert_select "meta[name='robots'][content='noindex,follow']"
    assert_select ".geo-guide", count: 0
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
