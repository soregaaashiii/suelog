require "test_helper"
require_relative "../support/search_console_test_helpers"

class ArticlePageLinksRenderingTest < ActionDispatch::IntegrationTest
  include SearchConsoleTestHelpers
  UA = { "User-Agent" => "Mozilla/5.0 Chrome/138.0 Safari/537.36" }.freeze
  setup do
    seed_gsc_catalog
    Article.update_all(published: false)
    @shop = Shop.find_by!(name: "実績テスト0")
    @article = Article.create!(title: "この店舗の紹介", slug: "introduced-shop", summary: "紹介するお店の情報", body: "[shop id=#{@shop.id}]", published: true, published_at: 60.days.ago)
    31.times { |i| Article.create!(title: "別記事#{i}", slug: "unrelated-#{i}", body: "別の内容", published: true, published_at: 1.day.ago) }
  end

  test "existing article shop links remain and geographic links return to published lists" do
    get article_path(@article), headers: UA
    assert_response :success
    assert_select ".article-body a[href*='shop_id=#{@shop.id}']"
    assert_select ".article-geographic-links a[href='/areas/suita']", count: 1
    assert_select ".article-geographic-links a[href='/stations/esaka']", count: 1
    get "/areas/suita/genre/izakaya", headers: UA
    assert_response :success
    assert_select ".geo-articles a[href='#{article_path(@article)}']", count: 1
    assert_select ".geo-articles a", count: 1
    get "/areas/suita/smoking/smoking-room", headers: UA
    assert_select ".geo-articles", count: 0
  end

  test "shop prioritizes its actual source beyond the old latest thirty article limit" do
    get shop_path(@shop), headers: UA
    assert_response :success
    assert_select ".shop-show__relatedArticles h2", text: "この店舗を紹介する記事"
    assert_select ".shop-show__relatedArticles a[href='#{article_path(@article)}']"
    assert_select ".shop-show__relatedArticles a", count: 1
    get "/areas/suita", params: { genre: "居酒屋" }, headers: UA
    assert_select ".geo-articles", count: 0
  end
end
