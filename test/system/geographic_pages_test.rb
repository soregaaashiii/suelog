require "application_system_test_case"

class GeographicPagesTest < ApplicationSystemTestCase
  setup do
    Shop.update_all(approved: false, on_hold: false)
    Article.update_all(published: false)
    Rails.cache.clear
    now = Time.current
    Shop.insert_all!(Array.new(12) do |i|
      { name: "江坂の店舗#{i}", address: "大阪府吹田市江坂町1-#{i}", nearest_station: "江坂駅から#{100 + i}m",
        genre: "居酒屋", approved: true, on_hold: false, rejected: false, smoking_area: 1, smoking_type: 0,
        last_confirmed_on: Date.current, created_at: now, updated_at: now }
    end)
  end

  test "navigate hub region and station on desktop and mobile without horizontal overflow" do
    visit "/areas"
    assert_selector "h1", text: "大阪の地域・駅から喫煙できる店を探す"
    page.save_screenshot(Rails.root.join("tmp/geography-hub.png"))
    click_link "吹田市"
    assert_selector "h1", text: "吹田市で喫煙できる店"
    assert_selector ".geo-context", text: "掲載店舗は12件"
    assert_selector ".shop-card__titleLink", count: 12
    page.execute_script("document.querySelector('.geo-context').scrollIntoView()")
    page.save_screenshot(Rails.root.join("tmp/geography-desktop.png"))
    find('.geo-context a[href="/stations/esaka"]').click
    assert_selector "h1", text: "江坂駅周辺で喫煙できる店"
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
    page.execute_script("document.querySelector('.geo-context').scrollIntoView()")
    page.save_screenshot(Rails.root.join("tmp/geography-mobile.png"))
    find('.geo-context a[href="/areas/suita"]').click
    assert_selector "h1", text: "吹田市で喫煙できる店"
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
