require "application_system_test_case"
require_relative "../support/search_console_test_helpers"

class ArticlePageLinksSystemTest < ApplicationSystemTestCase
  include SearchConsoleTestHelpers
  setup do
    seed_gsc_catalog
    Article.update_all(published: false)
    @shop = Shop.find_by!(name: "実績テスト0")
    @article = Article.create!(title: "吹田のお店を紹介", slug: "suita-linked-guide", summary: "実際に掲載したお店の喫煙条件を確認できます。", body: "[shop id=#{@shop.id}]", published: true)
  end

  test "navigate geographic article and shop links on desktop and mobile" do
    visit "/areas/suita/genre/izakaya"
    assert_selector ".geo-articles a", text: @article.title
    settle_images
    scroll_to(".geo-articles")
    find(".geo-articles").native.save_screenshot(Rails.root.join("tmp/article-links-region-desktop.png"))
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
    find(".geo-articles").native.save_screenshot(Rails.root.join("tmp/article-links-region-mobile.png"))
    within(".geo-articles") { click_link @article.title }
    assert_selector "h1", text: @article.title
    assert_selector ".article-geographic-links a[href='/stations/esaka']"
    settle_images
    scroll_to(".article-geographic-links")
    page.save_screenshot(Rails.root.join("tmp/article-links-article-mobile.png"))
    within(".article-geographic-links") { click_link "吹田市の店舗一覧" }
    assert_selector "h1", text: "吹田市で喫煙できる店"
    within(".geo-articles") { click_link @article.title }
    within(".article-body") { find(".refine-article-shop-card").click }
    assert_selector "h1", text: @shop.name
    assert_selector ".shop-show__relatedArticles h2", text: "この店舗を紹介する記事"
    within(".shop-show__relatedArticles") { click_link @article.title }
    assert_selector "h1", text: @article.title
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
  private

  def scroll_to(selector)
    page.driver.browser.execute_async_script(<<~JS, selector)
      const selector = arguments[0], done = arguments[1];
      requestAnimationFrame(() => requestAnimationFrame(() => {
        document.querySelector(selector).scrollIntoView({ behavior: 'instant', block: 'start' });
        requestAnimationFrame(done);
      }));
    JS
  end

  def settle_images
    page.execute_script("document.querySelectorAll('img').forEach(img => img.loading = 'eager')")
    Selenium::WebDriver::Wait.new(timeout: 5).until { page.evaluate_script("Array.from(document.images).every(img => img.complete)") }
  end

end
