require "application_system_test_case"

class HorizontalShopCardsTest < ApplicationSystemTestCase
  test "photos and fallback stay left of linked title and details at all screen sizes" do
    previous_transformer = ActiveStorage.variant_transformer
    ActiveStorage.variant_transformer = ActiveStorage::Transformers::ImageMagick
    Shop.update_all(approved: false)
    Geocoder.configure(lookup: :test)
    Geocoder::Lookup::Test.set_default_stub([])
    attrs = { address: "大阪市北区梅田1-1", nearest_station: "梅田駅から100m", genre: "カフェ",
      last_confirmed_on: Date.current, smoking_area: :all_smoking, smoking_type: :both_ok, approved: true }
    photo_shop = Shop.create!(**attrs, name: "写真ありの喫茶店")
    2.times do |i|
      photo_shop.food_photos.attach(io: File.open(Rails.root.join("app/assets/images/fallbacks/cafe.jpg")), filename: "cafe#{i}.jpg", content_type: "image/jpeg")
    end
    Shop.create!(**attrs, name: "画像なしのとても長い店名でも詳細を読めることを確認する喫茶店")
    [1280, 390, 320].each do |width|
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: 900, deviceScaleFactor: 1, mobile: width < 640)
      visit "/?q=喫茶店"
      assert_selector ".shop-card", count: 2
      assert_selector ".shop-card__body .shop-card__titleLink", count: 2
      assert_selector ".shop-card__imageNote", text: "イメージ画像", count: 1
      assert_selector "[data-shop-card-slider]", count: 1
      assert_selector 'button[aria-label="次の画像"]', count: 1
      assert page.evaluate_script(<<~JS)
        [...document.querySelectorAll('.shop-card')].every(card => {
          const image = card.querySelector('.shop-card__mediaLink').getBoundingClientRect();
          const body = card.querySelector('.shop-card__body').getBoundingClientRect();
          const title = card.querySelector('.shop-card__titleLink').getBoundingClientRect();
          return image.width >= 90 && image.right <= body.left && title.left >= body.left &&
            body.right <= card.getBoundingClientRect().right && image.top < title.bottom;
        }) && document.documentElement.scrollWidth <= #{width}
      JS
      page.execute_script("document.querySelectorAll('.shop-card img').forEach(img => img.loading = 'eager')")
      Selenium::WebDriver::Wait.new(timeout: 10).until { page.evaluate_script("[...document.querySelectorAll('.shop-card img')].every(img => img.complete && img.naturalWidth > 0)") }
      page.execute_script("document.querySelector('.shop-grid').scrollIntoView({block: 'start'})")
      page.driver.browser.execute_async_script("const done = arguments[0]; requestAnimationFrame(() => requestAnimationFrame(done));")
      page.save_screenshot(Rails.root.join("tmp/horizontal-shop-cards-#{width}.png"))
    end
    within ".shop-card", text: "写真ありの喫茶店" do
      find(".shop-card__body .shop-card__titleLink").click
    end
    assert_current_path shop_path(photo_shop)
  ensure
    ActiveStorage.variant_transformer = previous_transformer
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
