require "application_system_test_case"

class AdminSeoPagesTest < ApplicationSystemTestCase
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
    credentials = Rails.root.join("app/controllers/admin/base_controller.rb").read.match(/name:\s*"([^"]+)",\s*password:\s*"([^"]+)"/)
    raise "Admin authentication configuration changed" unless credentials
    server = Capybara.current_session.server
    username, password = credentials.captures.map { |part| ERB::Util.url_encode(part) }
    visit "http://#{username}:#{password}@#{server.host}:#{server.port}#{admin_seo_pages_path}"
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
end
