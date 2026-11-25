require "test_helper"

class Admin::SeoPagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    credentials = Rails.root.join("app/controllers/admin/base_controller.rb").read.match(/name:\s*"([^"]+)",\s*password:\s*"([^"]+)"/)
    raise "Admin authentication configuration changed" unless credentials
    @headers = { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(credentials[1], credentials[2]) }
    Shop.update_all(approved: false, on_hold: false)
    Rails.cache.clear
    now = Time.current
    Shop.insert_all!(Array.new(20) do |i|
      { name: "SEO店舗#{i}", address: "大阪府吹田市江坂町1-1", nearest_station: "江坂駅から100m",
        genre: i < 12 ? "居酒屋" : "カフェ", approved: true, on_hold: false, smoking_unverified: false,
        smoking_area: i < 15 ? 1 : 0, smoking_type: 0, last_confirmed_on: Date.current, created_at: now, updated_at: now }
    end)
  end

  test "inventory requires administrator authentication" do
    get admin_seo_pages_path
    assert_response :unauthorized
    assert_select "#seo-pages-title", count: 0
  end

  test "authenticated inventory filters and displays truthful statuses canonical URLs and reasons" do
    get admin_seo_pages_path, params: { q: "吹田 居酒屋", kind: "genre", status: "index" }, headers: @headers
    assert_response :success
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select "h1", text: "SEOページ一覧"
    assert_select ".admin-nav a[href='#{admin_seo_pages_path}']", text: "SEOページ"
    assert_select "tr[data-seo-path]", count: 1
    assert_select "tr[data-seo-path='/areas/suita/genre/izakaya'][data-seo-status='index']" do
      assert_select "td", text: /掲載基準を満たす/
      assert_select "a[href='https://suelog.jp/areas/suita/genre/izakaya']", count: 2
    end
    assert_select ".admin-seo__note", text: /Googleへのインデックス登録状況ではありません/
    get admin_seo_pages_path, params: { q: "/stations/esaka/genre/izakaya", reason: "duplicate" }, headers: @headers
    assert_select "tr[data-seo-status='noindex']" do
      assert_select "td", text: /同じ店舗集合のページあり/
      assert_select "a[href='https://suelog.jp/areas/suita/genre/izakaya']", count: 1
    end
    get admin_seo_pages_path, params: { q: "/areas/sakai-naka", kind: "region", status: "not_found" }, headers: @headers
    assert_select "tr[data-seo-status='not_found']" do
      assert_select "td", text: /404のため設定なし/
      assert_select "a", count: 0
    end
  end

  test "pagination retains filters and handles empty results and invalid options" do
    get admin_seo_pages_path, params: { status: "not_found", sort: "url" }, headers: @headers
    assert_select "tr[data-seo-path]", count: 50
    assert_select ".km-pagination a[href*='page=2'][href*='status=not_found'][href*='sort=url']"
    get admin_seo_pages_path, params: { status: "not_found", sort: "url", page: 2 }, headers: @headers
    assert_response :success
    assert_select "tr[data-seo-path]", count: 50
    get admin_seo_pages_path, params: { q: "見つからない地名", kind: "unsupported", sort: "unknown", page: -1 }, headers: @headers
    assert_response :success
    assert_select ".admin-seo__empty", text: /該当するページはありません/
    assert_select "select#sort option[selected][value='shops_desc']"
    assert_select "tr[data-seo-path]", count: 0
  end
end
