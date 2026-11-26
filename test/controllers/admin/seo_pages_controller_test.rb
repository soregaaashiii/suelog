require "test_helper"
require_relative "../../support/search_console_test_helpers"

class Admin::SeoPagesControllerTest < ActionDispatch::IntegrationTest
  include SearchConsoleTestHelpers
  teardown { close_gsc_files }

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
      assert_select "a[href^='https://suelog.jp/']", count: 0
      assert_select "a", text: "SEO設定を編集"
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
  test "CSV upload is authenticated and successful imports display metrics and candidate filters" do
    current = gsc_csv(["https://suelog.jp/areas/suita", 5, 1000, "0.5%", 12])
    previous = gsc_csv(["https://suelog.jp/areas/suita", 20, 1500, "1.33%", 10])
    assert_no_difference "SearchConsoleImport.count" do
      post admin_import_seo_pages_path, params: { search_console_import: gsc_attributes.merge(current_file: gsc_upload(current)) }
      assert_response :unauthorized
    end
    assert_difference "SearchConsoleImport.count", 1 do
      post admin_import_seo_pages_path, params: { search_console_import: gsc_attributes(comparison: true).merge(current_file: gsc_upload(current), previous_file: gsc_upload(previous)) }, headers: @headers
      assert_equal 303, response.status, css_select(".admin-seo__importError").map(&:text).join
    end
    report = SearchConsoleImport.order(:id).last
    assert_redirected_to admin_seo_pages_path(import_id: report.id)
    get admin_seo_pages_path, params: { import_id: report.id, performance: "low_ctr" }, headers: @headers
    assert_response :success
    assert_select "tr[data-seo-path]", count: 1
    assert_select "tr[data-seo-path='/areas/suita']" do
      assert_select ".admin-seo__metric", count: 4
      assert_select ".admin-seo__metric", text: /0.50%/
      assert_select ".admin-seo__metric", text: /前期間比 -15/
      assert_select ".admin-seo__candidates", text: /クリック数が減少/
    end
    assert_select "select#import_id option[selected][value='#{report.id}']"
    assert_select ".admin-seo__searchConsole", text: /0クリックや未登録を意味しません/
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "invalid CSV preserves prior snapshots and renders actionable errors" do
    csv = gsc_csv(["https://suelog.jp/areas/suita", 1, 100, "1%", 8])
    prior = SearchConsoleCsvImporter.new(current_file: gsc_upload(csv), attributes: gsc_attributes).call
    assert_no_difference ["SearchConsoleImport.count", "SearchConsolePageMetric.count"] do
      post admin_import_seo_pages_path, params: { search_console_import: gsc_attributes.merge(current_file: gsc_upload("bad,csv\nno,data\n")) }, headers: @headers
      assert_response :unprocessable_entity
    end
    assert_select ".admin-seo__importError", text: /ページ別/
    assert_select "select#import_id option[selected][value='#{prior.id}']"
    assert_select "input#search_console_import_period_start[value='#{gsc_attributes[:period_start]}']"
    get admin_seo_pages_path, params: { import_id: 999999999 }, headers: @headers
    assert_response :not_found
  end

  test "snapshots can be selected and are retained across pagination and filters" do
    reports = [2, 8].map do |clicks|
      SearchConsoleCsvImporter.new(current_file: gsc_upload(gsc_csv(["https://suelog.jp/areas/suita", clicks, 100, "#{clicks}%", 8])), attributes: gsc_attributes).call
    end
    get admin_seo_pages_path, params: { import_id: reports.first.id, q: "/areas/suita", kind: "region" }, headers: @headers
    assert_select "tr[data-seo-path='/areas/suita'] .admin-seo__metric strong", text: "2"
    get admin_seo_pages_path, params: { import_id: reports.last.id, q: "/areas/suita", kind: "region" }, headers: @headers
    assert_select "tr[data-seo-path='/areas/suita'] .admin-seo__metric strong", text: "8"
    get admin_seo_pages_path, params: { import_id: reports.first.id, performance: "no_data" }, headers: @headers
    assert_select "tr[data-seo-path]", count: 50
    assert_select ".km-pagination a[href*='page=2'][href*='import_id=#{reports.first.id}'][href*='performance=no_data']"
    assert_select ".admin-seo__metric strong", text: "—", count: 200
  end

  test "priority shortcuts select candidates and preserve the chosen report in edit links" do
    report = SearchConsoleCsvImporter.new(current_file: gsc_upload(gsc_csv(["https://suelog.jp/areas/suita", 5, 1000, "0.5%", 12])), attributes: gsc_attributes).call
    get admin_seo_pages_path, params: { import_id: report.id }, headers: @headers
    assert_response :success
    assert_select "select#sort option[selected][value='priority']"
    assert_select ".admin-seo__candidateLinks a", text: "表示は多いがCTRが低い（1件）"
    assert_select ".admin-seo__candidateLinks a[href*='performance=actionable'][href*='sort=priority'][href*='import_id=#{report.id}']"
    assert_equal "/areas/suita", css_select("tr[data-seo-path]").first["data-seo-path"]
    get admin_seo_pages_path, params: { import_id: report.id, performance: "actionable", sort: "priority" }, headers: @headers
    assert_select "tr[data-seo-path]", count: 1
    assert_select ".admin-seo__priority", text: "優先度 中"
    assert_select "a[href*='filters%5Bperformance%5D=actionable'][href*='filters%5Bimport_id%5D=#{report.id}']", text: "SEO設定を編集"
  end

end
