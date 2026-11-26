require "test_helper"
require_relative "../../support/search_console_test_helpers"

class Admin::SeoPageMetadataTest < ActionDispatch::IntegrationTest
  include SearchConsoleTestHelpers
  UA = { "User-Agent" => "Mozilla/5.0 Chrome/138.0 Safari/537.36" }.freeze
  setup do
    seed_gsc_catalog
    credentials = Rails.root.join("app/controllers/admin/base_controller.rb").read.match(/name:\s*"([^"]+)",\s*password:\s*"([^"]+)"/)
    raise "Admin authentication configuration changed" unless credentials
    @headers = { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(credentials[1], credentials[2]) }
    @path = "/areas/suita"
  end
  teardown { close_gsc_files }

  test "editing requires admin authentication and only accepts inventory URLs" do
    get admin_edit_seo_page_path, params: { page_path: @path }
    assert_response :unauthorized
    assert_no_difference ["SeoPageSetting.count", "SeoPageRevision.count"] do
      patch admin_update_seo_page_metadata_path, params: update_params("new", title: "未認証")
      assert_response :unauthorized
      ["/shops/1", "/areas", "/areas/unknown", "/areas/suita/genre/unknown", "/areas/suita?genre=cafe", "https://example.com/areas/suita"].each do |path|
        get admin_edit_seo_page_path, params: { page_path: path }, headers: @headers
        assert_response :not_found
      end
    end
  end

  test "saves from the inventory and updates public metadata without changing heading or canonical" do
    get admin_edit_seo_page_path, params: { page_path: @path, filters: { q: "吹田", status: "index" } }, headers: @headers
    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select "input#seo_page_setting_version[value='new']"
    assert_select "input#seo_page_setting_title[value]", count: 0
    assert_difference({ "SeoPageSetting.count" => 1, "SeoPageRevision.count" => 1 }) do
      patch admin_update_seo_page_metadata_path, params: update_params("new", title: "吹田の席で吸える店を探す｜吸えログ", description: "独自の紹介文", change_note: "検索実績を見て改訂"), headers: @headers
    end
    assert_response :see_other
    follow_redirect! headers: @headers
    assert_select ".seo-editor__history article", count: 1
    assert_select ".seo-editor__history", text: /検索実績を見て改訂/
    get @path, headers: UA
    assert_select "title", text: "吹田の席で吸える店を探す｜吸えログ"
    assert_select "meta[name='description'][content='独自の紹介文']"
    assert_select "meta[property='og:title'][content='吹田の席で吸える店を探す｜吸えログ']"
    assert_select "meta[name='twitter:description'][content='独自の紹介文']"
    assert_select "h1", text: "吹田市で喫煙できる店"
    assert_select "link[rel='canonical'][href='https://suelog.jp/areas/suita']"
    get admin_seo_pages_path, params: { q: "/areas/suita", kind: "region" }, headers: @headers
    assert_select "tr[data-seo-path='/areas/suita']", text: /個別設定あり/
    assert_select "tr[data-seo-path='/areas/suita'] a", text: "SEO設定を編集"
  end

  test "blank fields fall back individually and reset keeps noindex and history" do
    patch admin_update_seo_page_metadata_path, params: update_params("new", title: "個別タイトル", description: "個別説明"), headers: @headers
    setting = SeoPageSetting.find_by!(path: @path)
    patch admin_update_seo_page_metadata_path, params: update_params(setting.version_token, title: "", description: "説明だけ個別"), headers: @headers
    get @path, params: { open_now_only: "1" }, headers: UA
    assert_select "title", text: "吹田市で喫煙できる店｜吸えログ"
    assert_select "meta[name='description'][content='説明だけ個別']"
    assert_select "meta[name='robots'][content='noindex,follow']"
    assert_select "link[rel='canonical'][href='https://suelog.jp/areas/suita']"
    patch admin_update_seo_page_metadata_path, params: update_params(setting.reload.version_token, title: "無視するタイトル").merge(commit_action: "reset"), headers: @headers
    assert_response :see_other
    assert_not setting.reload.customized?
    assert_equal 3, setting.revisions.count
    get @path, headers: UA
    assert_match(/掲載店舗20件/, css_select("meta[name='description']").first["content"])
  end

  test "overrides are isolated by region station genre and smoking URL and retain duplicate canonicals" do
    paths = ["/stations/esaka", "/areas/suita/genre/izakaya", "/areas/suita/smoking/seat-smoking", "/stations/esaka/genre/izakaya"]
    paths.each_with_index do |path, i|
      @path = path
      patch admin_update_seo_page_metadata_path, params: update_params("new", title: "個別タイトル#{i}"), headers: @headers
      assert_response :see_other
      get path, headers: UA
      assert_select "title", text: "個別タイトル#{i}"
    end
    assert_select "meta[name='robots'][content='noindex,follow']"
    assert_select "link[rel='canonical'][href='https://suelog.jp/areas/suita/genre/izakaya']"
    get "/areas/suita", headers: UA
    assert_select "title", text: "吹田市で喫煙できる店｜吸えログ"
  end

  test "blank descriptions keep tracking updated shop counts after a title override" do
    patch admin_update_seo_page_metadata_path, params: update_params("new", title: "個別タイトル", description: ""), headers: @headers
    now = Time.current
    Shop.insert_all!([{ name: "追加店舗", address: "大阪府吹田市江坂町1-2", nearest_station: "江坂駅から100m", genre: "居酒屋", approved: true, on_hold: false, smoking_unverified: false, smoking_area: 1, smoking_type: 0, created_at: now, updated_at: now }])
    Rails.cache.clear
    get @path, headers: UA
    assert_select "title", text: "個別タイトル"
    assert_match(/掲載店舗21件/, css_select("meta[name='description']").first["content"])
  end

  test "inventory fetches edit status in one query rather than one query per row" do
    patch admin_update_seo_page_metadata_path, params: update_params("new", title: "個別タイトル"), headers: @headers
    queries = []
    callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] if payload[:sql].match?(/SELECT.*FROM ["`]?seo_page_settings/i) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get admin_seo_pages_path, headers: @headers }
    assert_response :success
    assert_select "tr[data-seo-path]", count: 50
    assert_equal 1, queries.length
  end

  test "zero-result pages remain 404 even when metadata is configured" do
    @path = "/areas/suita/smoking/heated-only"
    patch admin_update_seo_page_metadata_path, params: update_params("new", title: "将来の店舗向け設定"), headers: @headers
    assert_response :see_other
    get @path, headers: UA
    assert_response :not_found
  end

  test "invalid fields preserve input and concurrent edits return conflict with the current data" do
    patch admin_update_seo_page_metadata_path, params: update_params("new", title: "x" * 201), headers: @headers
    assert_response :unprocessable_entity
    assert_select ".seo-editor__error", text: /200文字/
    assert_select "input#seo_page_setting_title[value='#{'x' * 201}']"
    patch admin_update_seo_page_metadata_path, params: update_params("new", title: "保存済み"), headers: @headers
    assert_no_difference "SeoPageRevision.count" do
      patch admin_update_seo_page_metadata_path, params: update_params("new", title: "古い画面の入力"), headers: @headers
      assert_response :conflict
    end
    assert_select ".seo-editor__error", text: /別の画面/
    assert_select "input#seo_page_setting_title[value='保存済み']"
    assert_select "details", text: /古い画面の入力/
  end

  test "metadata is escaped in HTML and attribute contexts" do
    title = '\"><script>metadata-xss</script>'
    description = '\"><img src=x onerror=metadata-xss> & description'
    patch admin_update_seo_page_metadata_path, params: update_params("new", title: title, description: description), headers: @headers
    get @path, headers: UA
    assert_select "title", text: title
    assert_equal description, css_select("meta[name='description']").first["content"]
    assert_select "head script", text: /metadata-xss/, count: 0
    assert_select "head img", count: 0
  end

  test "history pagination and search metrics retain the inventory context without including form data in URLs" do
    csv = gsc_csv(["https://suelog.jp/areas/suita", 5, 1000, "0.5%", 12])
    report = SearchConsoleCsvImporter.new(current_file: gsc_upload(csv), attributes: gsc_attributes).call
    filters = { import_id: report.id, performance: "low_ctr", sort: "impressions_desc", q: "吹田" }
    11.times do |i|
      setting = SeoPageSetting.find_by(path: @path)
      patch admin_update_seo_page_metadata_path, params: update_params(setting&.version_token || "new", title: "タイトル#{i}").merge(filters: filters), headers: @headers
      assert_response :see_other
    end
    get admin_edit_seo_page_path, params: { page_path: @path, filters: filters, history_page: 2 }, headers: @headers
    assert_select ".seo-editor__history article", count: 1
    assert_select ".seo-editor__metrics strong", text: "0.50%"
    assert_select "a[href*='performance=low_ctr'][href*='import_id=#{report.id}']"
    setting = SeoPageSetting.find_by!(path: @path)
    patch admin_update_seo_page_metadata_path, params: update_params(setting.version_token, title: "x" * 201).merge(filters: filters), headers: @headers
    assert_response :unprocessable_entity
    assert_select ".seo-editor__pagination a[href*='history_page=2']"
    css_select(".seo-editor__pagination a").each { |link| assert_no_match(/seo_page_setting|authenticity_token/, link["href"]) }
  end

  test "task editing is authenticated independent and preserves filters with escaped notes" do
    params = { page_path: @path, filters: { task_status: "observing", comparison: "ready", q: "吹田", redirect: "https://evil.example" },
      seo_page_task: { version: "new", status: "observing", note: '<script>alert("test")</script>', handled_on: "", title: "ignored" } }
    patch admin_update_seo_page_task_path, params: params
    assert_response :unauthorized
    assert_no_difference ["SeoPageSetting.count", "SeoPageRevision.count"] do
      patch admin_update_seo_page_task_path, params: params, headers: @headers
      assert_response :see_other
    end
    assert_redirected_to admin_edit_seo_page_path(page_path: @path, filters: { task_status: "observing", comparison: "ready", q: "吹田" })
    follow_redirect! headers: @headers
    assert_select "#seo-task select option[selected][value='observing']"
    assert_select "#seo-task script", count: 0
    assert_select "textarea#seo_page_task_note", text: '<script>alert("test")</script>'
    assert_equal "no-store", response.headers["Cache-Control"]
    task = SeoPageTask.find_by!(path: @path)
    assert_equal Date.current, task.handled_on
    get admin_seo_pages_path, params: { task_status: "observing" }, headers: @headers
    assert_select "tr[data-seo-path]", count: 1
    assert_select ".admin-seo__task", text: /経過観察/
    assert_select "a[href*='filters%5Btask_status%5D=observing']", text: "対応状況を編集"
    get admin_seo_pages_path, params: { task_status: "completed" }, headers: @headers
    assert_select "tr[data-seo-path]", count: 0
  end

  test "invalid tasks retain input and stale tasks retain draft while displaying the latest state" do
    base = { page_path: @path, seo_page_task: { version: "new", status: "completed", handled_on: (Date.current + 1).iso8601, note: "保存前のメモ" } }
    patch admin_update_seo_page_task_path, params: base, headers: @headers
    assert_response :unprocessable_entity
    assert_select "textarea#seo_page_task_note", text: "保存前のメモ"
    assert_select "#seo-task .seo-editor__error", text: /今日以前/
    task = SeoPageTask.create!(path: @path, status: "in_progress", note: "現在のメモ")
    patch admin_update_seo_page_task_path, params: base, headers: @headers
    assert_response :conflict
    assert_select "#seo-task .seo-editor__error", text: /別の画面/
    assert_select "#seo-task", text: /保存前のメモ/
    assert_select "textarea#seo_page_task_note", text: "現在のメモ"
    assert_equal "in_progress", task.reload.status
    patch admin_update_seo_page_task_path, params: { page_path: "/shops/1", seo_page_task: { version: "new", status: "completed" } }, headers: @headers
    assert_response :not_found
  end

  private

  def update_params(version, **attributes)
    { page_path: @path, seo_page_setting: attributes.merge(version: version) }
  end
end
