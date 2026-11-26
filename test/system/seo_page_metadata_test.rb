require "application_system_test_case"
require_relative "../support/search_console_test_helpers"

class SeoPageMetadataTest < ApplicationSystemTestCase
  include SearchConsoleTestHelpers
  setup { seed_gsc_catalog }
  teardown { close_gsc_files }

  test "edit from a performance candidate publish metadata restore defaults and return to filtered results" do
    report = SearchConsoleCsvImporter.new(current_file: gsc_upload(gsc_csv(["https://suelog.jp/areas/suita", 5, 1000, "0.5%", 12])), attributes: gsc_attributes).call
    filters = { import_id: report.id, performance: "low_ctr", q: "吹田" }
    authenticate_at(admin_seo_pages_path(filters))
    assert_selector "tr[data-seo-path]", count: 1
    within("tr[data-seo-path='/areas/suita']") { click_link "SEO設定を編集" }
    assert_selector "h1", text: "SEO設定の編集"
    assert_selector ".seo-editor__metrics strong", text: "0.50%"
    fill_in "検索用タイトル", with: "吹田で喫煙できる店を探す｜吸えログ"
    fill_in "説明文（meta description）", with: "吹田市のお店の喫煙条件を確認できます。"
    fill_in "変更メモ（任意）", with: "検索実績からタイトルを改善"
    click_button "保存して反映"
    assert_text "SEO設定を保存しました。"
    assert_selector ".seo-editor__history article", count: 1
    page.execute_script("document.querySelector('.seo-editor__form').scrollIntoView()")
    page.save_screenshot(Rails.root.join("tmp/seo-metadata-desktop.png"))
    visit "/areas/suita"
    assert_title "吹田で喫煙できる店を探す｜吸えログ", exact: true
    assert_selector "h1", text: "吹田市で喫煙できる店"
    assert_equal "吹田市のお店の喫煙条件を確認できます。", find("meta[name='description']", visible: :all)["content"]

    visit admin_edit_seo_page_path(page_path: "/areas/suita", filters: filters)
    fill_in "説明文（meta description）", with: ""
    click_button "保存して反映"
    assert_selector ".seo-editor__history article", count: 2
    visit "/areas/suita"
    assert_title "吹田で喫煙できる店を探す｜吸えログ", exact: true
    assert_match(/掲載店舗20件/, find("meta[name='description']", visible: :all)["content"])
    visit admin_edit_seo_page_path(page_path: "/areas/suita", filters: filters)
    click_button "自動生成に戻す"
    assert_selector ".seo-editor__history article", count: 3
    assert_field "検索用タイトル", with: ""
    assert_field "説明文（meta description）", with: ""
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
    page.execute_script("document.querySelector('.seo-editor__form').scrollIntoView()")
    page.save_screenshot(Rails.root.join("tmp/seo-metadata-mobile.png"))
    click_link "← SEOページ一覧に戻る"
    assert_selector "tr[data-seo-path]", count: 1
    assert_field "検索実績・改善候補", with: "low_ctr"
    assert_field "地域・駅・条件・URL", with: "吹田"
    assert_selector "tr[data-seo-path='/areas/suita']", text: "自動生成"
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    visit "/areas/suita"
    assert_title "吹田市で喫煙できる店｜吸えログ", exact: true
  end

  test "a stale browser form shows the latest settings and retains the unsaved draft" do
    authenticate_at(admin_edit_seo_page_path(page_path: "/areas/suita"))
    original = current_window
    another = open_new_window
    within_window another do
      visit admin_edit_seo_page_path(page_path: "/areas/suita")
      fill_in "検索用タイトル", with: "別画面で保存したタイトル"
      click_button "保存して反映"
      assert_text "SEO設定を保存しました。"
    end
    within_window original do
      fill_in "検索用タイトル", with: "古い画面の下書き"
      click_button "保存して反映"
      assert_selector ".seo-editor__error", text: /別の画面で設定が更新/
      assert_field "検索用タイトル", with: "別画面で保存したタイトル"
      assert_text "古い画面の下書き"
      assert_equal 1, SeoPageRevision.count
      fill_in "検索用タイトル", with: "確認後のタイトル"
      click_button "保存して反映"
      assert_text "SEO設定を保存しました。"
      assert_equal 2, SeoPageRevision.count
    end
    another.close
  end

  test "priority shortcuts lead to a change comparison and explain unavailable periods" do
    setting = SeoPageSetting.create!(path: "/areas/suita", title: "吹田の喫煙できる店")
    revision = setting.revisions.create!(created_at: 25.days.ago,
      before_values: { "effective_title" => "変更前" }, after_values: { "effective_title" => setting.title })
    attributes = { period_start: Date.current - 17, period_end: Date.current - 4,
      previous_start: Date.current - 45, previous_end: Date.current - 32, search_context: "ウェブ・すべてのデバイス" }
    report = SearchConsoleCsvImporter.new(
      current_file: gsc_upload(gsc_csv(["https://suelog.jp/areas/suita", 5, 1000, "0.5%", 13])),
      previous_file: gsc_upload(gsc_csv(["https://suelog.jp/areas/suita", 20, 1500, "1.33%", 9])), attributes: attributes).call
    authenticate_at(admin_seo_pages_path(import_id: report.id))
    within(".admin-seo__candidateLinks") { click_link "掲載順位が低下（1件）" }
    assert_selector "tr[data-seo-path]", count: 1
    assert_selector ".admin-seo__priority", text: "優先度 高"
    click_link "SEO設定を編集"
    within("article[data-revision-id='#{revision.id}'] .seo-editor__comparison") do
      assert_text "変更前後の検索実績"
      assert_text "前期間比 -15"
      assert_text "前期間比 +4.00"
      assert_text "変更当日は比較から除外"
    end
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
    page.execute_script("document.querySelector('.seo-editor__comparison').scrollIntoView()")
    page.save_screenshot(Rails.root.join("tmp/seo-priority-comparison-mobile.png"))
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    setting.revisions.create!(created_at: 10.days.ago, before_values: {}, after_values: {})
    visit admin_edit_seo_page_path(page_path: "/areas/suita", filters: { import_id: report.id })
    within("article[data-revision-id='#{revision.id}'] .seo-editor__comparison") do
      assert_text "別のSEO設定変更"
      assert_no_selector ".seo-editor__metrics"
    end
  end

  private

  def authenticate_at(path)
    credentials = Rails.root.join("app/controllers/admin/base_controller.rb").read.match(/name:\s*"([^"]+)",\s*password:\s*"([^"]+)"/)
    raise "Admin authentication configuration changed" unless credentials
    server = Capybara.current_session.server
    username, password = credentials.captures.map { |part| ERB::Util.url_encode(part) }
    visit "http://#{username}:#{password}@#{server.host}:#{server.port}#{path}"
  end
end
