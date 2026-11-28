require "application_system_test_case"

class ArticleShopImagesTest < ApplicationSystemTestCase
  test "inline and footer article cards use the same shop images as listings" do
    previous_transformer = ActiveStorage.variant_transformer
    ActiveStorage.variant_transformer = ActiveStorage::Transformers::ImageMagick
    Shop.update_all(approved: false)
    Article.update_all(published: false)
    Geocoder.configure(lookup: :test)
    Geocoder::Lookup::Test.set_default_stub([])
    attrs = { address: "大阪市北区梅田1-1", nearest_station: "梅田駅から100m", genre: "カフェ",
      last_confirmed_on: Date.current, smoking_area: :all_smoking, smoking_type: :both_ok, approved: true }
    photo_shop = Shop.create!(**attrs, name: "店舗写真のある喫茶店")
    photo_shop.food_photos.attach(io: File.open(Rails.root.join("app/assets/images/fallbacks/yakitori.jpg")), filename: "actual-shop.jpg", content_type: "image/jpeg")
    fallback_shop = Shop.create!(**attrs, name: "店舗に対応するカフェ画像の喫茶店")
    article = Article.create!(title: "画像を含む店舗の紹介記事", slug: "shop-image-layout", body: "[shop id=#{photo_shop.id}]\n[shop id=#{fallback_shop.id}]", published: true)
    [1280, 390, 320].each do |width|
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: 900, deviceScaleFactor: 1, mobile: width < 640)
      visit article_path(article)
      assert_selector ".refine-article-shop-card", count: 2
      assert_selector ".refine-article-shop-card__photo img[src*='actual-shop.jpg']", count: 1
      assert_selector ".refine-article-shop-card__photo img[src*='fallbacks/cafe-']", count: 1
      assert_selector ".refine-article-shop-list__photo img[src*='fallbacks/cafe-']", count: 1
      assert_no_selector ".refine-article-shop-list__photo img[src*='other-']"
      assert page.evaluate_script(<<~JS)
        [...document.querySelectorAll('.refine-article-shop-card')].every(card => {
          const image = card.querySelector('.refine-article-shop-card__photo').getBoundingClientRect();
          const body = card.querySelector('.refine-article-shop-card__body').getBoundingClientRect();
          return image.width >= 80 && image.right <= body.left && body.right <= card.getBoundingClientRect().right;
        }) && document.documentElement.scrollWidth <= #{width}
      JS
      page.execute_script("document.querySelectorAll('.article-body img').forEach(img => img.loading = 'eager')")
      Selenium::WebDriver::Wait.new(timeout: 10).until { page.evaluate_script("[...document.querySelectorAll('.article-body img')].every(img => img.complete && img.naturalWidth > 0)") }
      page.driver.browser.execute_async_script("const done=arguments[0]; document.querySelector('.refine-article-shop-card').scrollIntoView(); requestAnimationFrame(() => requestAnimationFrame(done));")
      page.save_screenshot(Rails.root.join("tmp/article-shop-images-#{width}.png"))
    end
    find(".refine-article-shop-card", text: photo_shop.name).click
    assert_current_path shop_path(photo_shop)
    visit "/?q=喫茶店"
    assert_selector ".shop-card__img[src*='fallbacks/cafe-']", count: 1
    page.execute_script("document.querySelectorAll('.shop-card img').forEach(img => img.loading = 'eager')")
    Selenium::WebDriver::Wait.new(timeout: 10).until { page.evaluate_script("[...document.querySelectorAll('.shop-card img')].every(img => img.complete && img.naturalWidth > 0)") }
  ensure
    ActiveStorage.variant_transformer = previous_transformer
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
