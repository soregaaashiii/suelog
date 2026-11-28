require "application_system_test_case"

class KeywordSearchTest < ApplicationSystemTestCase
  test "existing search form handles spelling variants on desktop and mobile" do
    Shop.update_all(approved: false)
    Geocoder.configure(lookup: :test)
    Geocoder::Lookup::Test.set_default_stub([])
    Shop.create!(name: "Ｃａｆｅ・ＢＯＮＤ", address: "大阪府大阪市浪速区難波1-1", nearest_station: "なんば駅",
      genre: "カフェ", last_confirmed_on: Date.current, smoking_area: :all_smoking, smoking_type: :both_ok, approved: true)
    visit "/"
    fill_in "q", with: "cafebond ナンバ"
    find('input[type="submit"][value="検索"]').click
    assert_selector ".shop-card__titleLink", text: "Ｃａｆｅ・ＢＯＮＤ", count: 1
    assert_field "q", with: "cafebond ナンバ"
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    fill_in "q", with: "かふぇ"
    fill_in "station", with: "難波"
    find('input[type="submit"][value="検索"]').click
    assert_selector ".shop-card__titleLink", text: "Ｃａｆｅ・ＢＯＮＤ", count: 1
    assert_field "station", with: "難波"
    fill_in "q", with: "Cafe｜BOND"
    find('input[type="submit"][value="検索"]').click
    assert_selector ".shop-card__titleLink", text: "Ｃａｆｅ・ＢＯＮＤ", count: 1
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
