require "application_system_test_case"
require_relative "../support/search_console_test_helpers"

class AdminSeoPagesTest < ApplicationSystemTestCase
  include SearchConsoleTestHelpers
  teardown { close_gsc_files }

  setup do
    Shop.update_all(approved: false, on_hold: false)
    Rails.cache.clear
    now = Time.current
    Shop.insert_all!(Array.new(20) do |i|
      { name: "SEO店舗#{i}", address: "大阪府吹田市江坂町1-1", nearest_station: "江坂駅から100m",
        genre: i < 12 ? "居酒屋" : "カフェ", approved: true, on_hold: false, smoking_unverified: false,
        smoking_area: i < 15 ? 1 : 0, smoking_type: 0, last_confirmed_on: Date.current, created_at: now, updated_at: now }
    end)
  end

  test "admin can inspect filter and paginate SEO candidates on desktop and mobile" do
    open_seo_inventory
    assert_selector "h1", text: "SEOページ一覧"
    assert_selector "tr[data-seo-path]", count: 50
    page.execute_script("document.querySelector('.admin-seo').scrollIntoView()")
    page.save_screenshot(Rails.root.join("tmp/admin-seo-desktop.png"))

    fill_in "地域・駅・条件・URL", with: "吹田 居酒屋"
    select "ジャンル別", from: "ページ種別"
    select "index対象", from: "判定"
    click_button "絞り込む"
    assert_selector "tr[data-seo-path]", count: 1
    assert_selector "tr[data-seo-path='/areas/suita/genre/izakaya']", text: "掲載基準を満たす"
    fill_in "地域・駅・条件・URL", with: "江坂 居酒屋"
    select "noindex", from: "判定"
    select "同じ店舗集合のページあり", from: "判定理由"
    click_button "絞り込む"
    assert_selector "tr[data-seo-path='/stations/esaka/genre/izakaya']", text: "同じ店舗集合のページあり"
    assert_selector "tr[data-seo-path]", count: 1
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
    assert page.evaluate_script("(() => { const table = document.querySelector('.admin-seo__tableWrap'); return table.scrollWidth > table.clientWidth; })()")
    page.execute_script("document.querySelector('.admin-seo__filters').scrollIntoView()")
    page.save_screenshot(Rails.root.join("tmp/admin-seo-mobile.png"))
    find('.admin-seo__summaryItem', text: "404対象").click
    assert_selector "tr[data-seo-status='not_found']", count: 50
    find('.km-page--next').click
    assert_selector ".km-pagination [aria-current='page']", text: "2"
    assert_selector "tr[data-seo-status='not_found']", count: 50
    assert_selector "select#status option[selected][value='not_found']", visible: :all
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
  test "upload comparison CSV inspect changes and switch saved imports on mobile" do
    open_seo_inventory
    current = gsc_upload(gsc_csv(["https://suelog.jp/areas/suita", 5, 1000, "0.5%", 12]))
    previous = gsc_upload(gsc_csv(["https://suelog.jp/areas/suita", 20, 1500, "1.33%", 10]))
    attach_file "対象期間のページ別CSV", current.path
    attach_file "比較期間のページ別CSV", previous.path
    fill_gsc_dates(comparison: true)
    click_button "検索実績を取り込む"
    assert_text "検索実績を取り込みました。"
    first_report = SearchConsoleImport.order(:id).last
    select "表示は多いがCTRが低い", from: "検索実績・改善候補"
    click_button "絞り込む"
    assert_selector "tr[data-seo-path]", count: 1
    assert_selector "tr[data-seo-path='/areas/suita'] .admin-seo__metric", text: /0.50%/
    assert_selector "tr[data-seo-path='/areas/suita'] .admin-seo__metric", text: /前期間比 -15/
    page.execute_script("document.querySelector('.admin-seo__filters').scrollIntoView()")
    page.save_screenshot(Rails.root.join("tmp/search-console-desktop.png"))

    find("summary", text: "ページ別CSVを取り込む").click
    second = gsc_upload(gsc_csv(["https://suelog.jp/areas/suita", 8, 1000, "0.8%", 10]))
    attach_file "対象期間のページ別CSV", second.path
    fill_gsc_dates
    click_button "検索実績を取り込む"
    assert_text "検索実績を取り込みました。"
    assert_equal 2, SearchConsoleImport.count
    assert_selector "tr[data-seo-path='/areas/suita'] .admin-seo__metric strong", text: "8", exact_text: true
    find("#import_id option[value='#{first_report.id}']").select_option
    select "クリック数が減少", from: "検索実績・改善候補"
    click_button "絞り込む"
    assert_selector "tr[data-seo-path]", count: 1
    assert_selector "tr[data-seo-path='/areas/suita'] .admin-seo__metric", text: /前期間比 -15/
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
    page.execute_script("document.querySelector('.admin-seo__filters').scrollIntoView()")
    page.save_screenshot(Rails.root.join("tmp/search-console-mobile.png"))
    find("summary", text: "ページ別CSVを取り込む").click
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
    page.execute_script("document.querySelector('.admin-seo__importForm').scrollIntoView()")
    page.save_screenshot(Rails.root.join("tmp/search-console-upload-mobile.png"))
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  private

  def fill_gsc_dates(comparison: false)
    attributes = gsc_attributes(comparison: comparison)
    attributes.except(:search_context).each do |key, value|
      find("#search_console_import_#{key}").set(Date.iso8601(value))
    end
    fill_in "検索条件メモ（比較する場合は両期間で同じ条件）", with: attributes[:search_context]
  end

  def open_seo_inventory
    credentials = Rails.root.join("app/controllers/admin/base_controller.rb").read.match(/name:\s*"([^"]+)",\s*password:\s*"([^"]+)"/)
    raise "Admin authentication configuration changed" unless credentials
    server = Capybara.current_session.server
    username, password = credentials.captures.map { |part| ERB::Util.url_encode(part) }
    visit "http://#{username}:#{password}@#{server.host}:#{server.port}#{admin_seo_pages_path}"
  end

end
