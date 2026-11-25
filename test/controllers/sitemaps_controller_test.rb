require "test_helper"

class SitemapsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Shop.update_all(approved: false, on_hold: false)
    Article.update_all(published: false)
    Rails.cache.clear
  end

  test "index advertises live shop and article shards for crawlers without a browser user agent" do
    shop = create_shop
    article = Article.create!(title: "公開記事", slug: "public-sitemap", published: true, published_at: 1.day.ago)
    get "/sitemap.xml", headers: { "Host" => "attacker.example" }
    assert_response :success
    assert_equal "application/xml", response.media_type
    assert_includes response.headers["Cache-Control"], "max-age=300"
    assert_includes locations, "https://suelog.jp/sitemaps/shops/#{shop.id / 1000}.xml"
    assert_includes locations, "https://suelog.jp/sitemaps/articles/#{article.id / 1000}.xml"
    assert_includes locations, "https://suelog.jp/sitemaps/pages.xml"
    assert locations.all? { |url| url.start_with?("https://suelog.jp/") }
  end

  test "shop shard includes new public shops and real modification times but excludes private and held shops" do
    shop = create_shop
    private_shop = create_shop(approved: false)
    held_shop = create_shop(on_hold: true)
    get "/sitemaps/shops/#{shop.id / 1000}.xml"
    assert_response :success
    assert_includes locations, "https://suelog.jp/shops/#{shop.id}"
    assert_not_includes locations, "https://suelog.jp/shops/#{private_shop.id}"
    assert_not_includes locations, "https://suelog.jp/shops/#{held_shop.id}"
    assert_equal shop.updated_at.iso8601, document.at_xpath("//s:url[s:loc='https://suelog.jp/shops/#{shop.id}']/s:lastmod", namespaces).text
  end

  test "article shard includes published slugs and excludes drafts and future publications" do
    article = Article.create!(title: "公開", slug: "published-seo", published: true, published_at: 1.day.ago)
    draft = Article.create!(title: "下書き", slug: "draft-seo")
    future = Article.create!(title: "予約", slug: "future-seo", published: true, published_at: 1.day.from_now)
    get "/sitemaps/articles/#{article.id / 1000}.xml"
    assert_response :success
    assert_includes locations, "https://suelog.jp/articles/#{article.slug}"
    assert_not_includes locations, "https://suelog.jp/articles/#{draft.slug}"
    assert_not_includes locations, "https://suelog.jp/articles/#{future.slug}"
  end

  test "stable ID boundaries put each shop in exactly one shard" do
    create_shop(id: 999)
    create_shop(id: 1000)
    get "/sitemaps/shops/0.xml"
    assert_includes locations, "https://suelog.jp/shops/999"
    assert_not_includes locations, "https://suelog.jp/shops/1000"
    get "/sitemaps/shops/1.xml"
    assert_includes locations, "https://suelog.jp/shops/1000"
    assert_not_includes locations, "https://suelog.jp/shops/999"
  end

  test "empty shards return not found instead of an empty successful page" do
    get "/sitemaps/shops/99999999.xml"
    assert_response :not_found
  end

  test "cached shop sitemap reflects visibility changes after its bounded lifetime" do
    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    shop = create_shop
    path = "/sitemaps/shops/#{shop.id / 1000}.xml"
    get path
    assert_includes locations, "https://suelog.jp/shops/#{shop.id}"
    shop.update_columns(approved: false)
    travel 6.minutes do
      get path
      assert_response :not_found
    end
  ensure
    Rails.cache = previous_cache
  end

  test "fixed pages use unique canonical URLs without search filters or submission forms" do
    get "/sitemaps/pages.xml"
    assert_response :success
    assert_includes locations, "https://suelog.jp/articles"
    assert_includes locations, "https://suelog.jp/umeda/genre/cafe"
    assert_equal locations.uniq, locations
    assert locations.none? { |url| url.include?("?") || url.end_with?("/new", "/contact") }
    assert document.xpath("//s:lastmod", namespaces).empty?
  end

  private

  def create_shop(**overrides)
    Shop.create!({ name: "サイトマップ対象", address: "大阪府大阪市北区梅田", approved: true,
      genre: "居酒屋", last_confirmed_on: Date.current, smoking_area: :all_smoking, smoking_type: :both_ok }.merge(overrides))
  end

  def document = Nokogiri::XML(response.body) { |config| config.strict }
  def namespaces = { "s" => PublicSitemap::NAMESPACE }
  def locations = document.xpath("//s:loc", namespaces).map(&:text)
end
