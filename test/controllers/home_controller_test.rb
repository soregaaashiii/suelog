require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/138.0 Safari/537.36"

  setup do
    Shop.update_all(approved: false, on_hold: false)
    Article.update_all(published: false)
  end

  test "renders the public home page with unchanged SEO and navigation" do
    insert_shops(shop_attributes(name: "公開店舗"))

    get root_url, headers: request_headers

    assert_response :success
    assert_select "title", "吸えログ in大阪｜大阪で喫煙できる飲食店を探せる"
    assert_select "meta[name='description'][content='大阪で喫煙できる飲食店を探せる吸えログ。席で喫煙可・喫煙所あり・加熱式のみなどの情報を掲載しています。']"
    assert_select "link[rel='canonical'][href='http://www.example.com/']"
    assert_select "meta[name='robots'][content='index,follow']"
    assert_select "script[type='application/ld+json']", count: 0
    assert_select "a[href='#{umeda_path}']", text: "梅田の一覧を見る"
    assert_select "a[href='#{namba_path}']", text: "難波の一覧を見る"
    assert_select ".result-hit-text", text: "1件ヒット"
    assert_select ".shop-card__titleLink", text: "公開店舗"
  end

  test "shows only approved shops that are not on hold" do
    insert_shops(
      shop_attributes(name: "表示対象"),
      shop_attributes(name: "未承認", approved: false),
      shop_attributes(name: "保留中", on_hold: true)
    )

    get root_url, headers: request_headers

    assert_response :success
    assert_select ".result-hit-text", text: "1件ヒット"
    assert_equal [ "表示対象" ], rendered_shop_names
    assert_no_match(/未承認|保留中/, response.body)
  end

  test "preserves every supported shop ordering" do
    now = Time.zone.local(2026, 7, 30, 12, 0, 0)
    ids = insert_shops(
      shop_attributes(name: "評価トップ", created_at: now - 3.hours),
      shop_attributes(name: "口コミトップ", created_at: now - 2.hours),
      shop_attributes(name: "新着トップ", created_at: now - 1.hour)
    )
    insert_reviews(
      *Array.new(3) { review_attributes(shop_id: ids[0], rating: 5) },
      *Array.new(5) { review_attributes(shop_id: ids[1], rating: 4) },
      review_attributes(shop_id: ids[2], rating: 3)
    )

    {
      "recommended" => %w[評価トップ 口コミトップ 新着トップ],
      "rating" => %w[評価トップ 口コミトップ 新着トップ],
      "reviews_count" => %w[口コミトップ 評価トップ 新着トップ],
      "newest" => %w[新着トップ 口コミトップ 評価トップ]
    }.each do |sort, expected|
      get root_url(sort:), headers: request_headers

      assert_response :success
      assert_equal expected, rendered_shop_names, "unexpected #{sort} order"
    end
  end

  test "keeps the same page size and pagination order" do
    now = Time.zone.local(2026, 7, 30, 12, 0, 0)
    insert_shops(
      *Array.new(31) do |index|
        shop_attributes(
          name: format("新着%02d", index),
          created_at: now - index.minutes
        )
      end
    )

    get root_url(sort: "newest"), headers: request_headers

    assert_response :success
    assert_select ".result-hit-text", text: "31件ヒット"
    assert_equal 30, rendered_shop_names.size
    assert_equal "新着00", rendered_shop_names.first
    assert_equal "新着29", rendered_shop_names.last

    get root_url(sort: "newest", page: 2), headers: request_headers

    assert_response :success
    assert_equal [ "新着30" ], rendered_shop_names
  end

  test "renders the empty state when no shops exist" do
    get root_url, headers: request_headers

    assert_response :success
    assert_select ".result-hit-text", text: "0件ヒット"
    assert_select ".shop-card", count: 0
    assert_select ".empty-state", text: /該当する店舗はありません/
  end

  test "area page shows only published recommended articles in the existing order" do
    insert_shops(shop_attributes(name: "梅田の店舗", area: "梅田", address: "大阪市北区梅田"))
    insert_articles(
      article_attributes(title: "公開2", slug: "published-2", recommended_order: 2),
      article_attributes(title: "公開1", slug: "published-1", recommended_order: 1),
      article_attributes(title: "非公開", slug: "draft", published: false, recommended_order: 0)
    )

    get umeda_url, headers: request_headers

    assert_response :success
    links = css_select("a[href^='/articles/']").map { |node| node.text.strip }
    assert_equal %w[公開1 公開2], links
    assert_no_match(/非公開/, response.body)
  end

  test "reflects shop and article additions and updates on the next request" do
    shop_id = insert_shops(
      shop_attributes(name: "更新前店舗", area: "梅田", address: "大阪市北区梅田")
    ).first
    article_id = insert_articles(
      article_attributes(title: "更新前記事", slug: "updated-article")
    ).first

    get umeda_url, headers: request_headers

    assert_response :success
    assert_includes rendered_shop_names, "更新前店舗"
    assert_select "a[href='/articles/updated-article']", text: "更新前記事"

    Shop.where(id: shop_id).update_all(name: "更新後店舗")
    Article.where(id: article_id).update_all(title: "更新後記事")
    insert_shops(shop_attributes(name: "追加店舗", area: "梅田", address: "大阪市北区梅田"))
    insert_articles(article_attributes(title: "追加記事", slug: "added-article", recommended_order: 1))

    get umeda_url, headers: request_headers

    assert_response :success
    assert_includes rendered_shop_names, "更新後店舗"
    assert_includes rendered_shop_names, "追加店舗"
    assert_select "a[href='/articles/updated-article']", text: "更新後記事"
    assert_select "a[href='/articles/added-article']", text: "追加記事"
    assert_no_match(/更新前店舗|更新前記事/, response.body)
  end

  test "loads full shop rows only for the visible page" do
    insert_shops(*Array.new(31) { |index| shop_attributes(name: format("店舗%02d", index)) })
    shop_sql = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |event|
      sql = event.payload[:sql].to_s.gsub(/\s+/, " ")
      shop_sql << sql if sql.include?('FROM "shops"') && sql.match?(/\ASELECT/i)
    end

    get root_url, headers: request_headers

    assert_response :success
    ranking_query = shop_sql.find { |sql| sql.include?("confirmed_on_sort") }
    full_row_query = shop_sql.find { |sql| sql.include?("shops.*") }
    assert ranking_query
    assert_not_includes ranking_query, "shops.*"
    assert full_row_query
    assert_match(/WHERE "shops"."id" IN/, full_row_query)
    assert_equal 30, rendered_shop_names.size
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  test "tracks one public page view per visitor per day" do
    assert_difference("PageView.count", 1) do
      2.times do
        get root_url, headers: request_headers("HTTP_USER_AGENT" => USER_AGENT)
        assert_response :success
      end
    end
  end

  test "has a partial index for the daily public page view lookup" do
    index = ActiveRecord::Base.connection.indexes(:page_views).find do |candidate|
      candidate.name == "index_page_views_on_daily_identity_without_shop"
    end

    assert index
    assert_equal %w[path ip_hash created_at], index.columns
    assert_equal "shop_id IS NULL", index.where
  end

  private

  def request_headers(extra = {})
    {
      "HTTP_HOST" => "www.example.com",
      "HTTP_USER_AGENT" => "Googlebot"
    }.merge(extra)
  end

  def rendered_shop_names
    css_select(".shop-card__titleLink").map { |node| node.text.strip }
  end

  def insert_shops(*rows)
    Shop.insert_all!(rows)
    rows.map { |row| Shop.find_by!(name: row.fetch(:name)).id }
  end

  def insert_reviews(*rows)
    Review.insert_all!(rows)
  end

  def insert_articles(*rows)
    Article.insert_all!(rows)
    rows.map { |row| Article.find_by!(slug: row.fetch(:slug)).id }
  end

  def shop_attributes(name:, **overrides)
    now = Time.zone.local(2026, 7, 30, 12, 0, 0)
    {
      name:,
      address: "大阪市北区梅田1-1",
      area: "梅田",
      genre: "居酒屋",
      nearest_station: "梅田駅",
      approved: true,
      rejected: false,
      on_hold: false,
      smoking_area: Shop.smoking_areas[:all_smoking],
      smoking_type: Shop.smoking_types[:both_ok],
      opening_hours_json: {},
      import_metadata: {},
      seat_type_tags: [],
      last_confirmed_on: Date.new(2026, 7, 30),
      created_at: now,
      updated_at: now
    }.merge(overrides)
  end

  def review_attributes(shop_id:, rating:)
    {
      shop_id:,
      rating:,
      approved: true,
      status: 0,
      author_name: "確認者",
      comment: "確認済み",
      created_at: Time.zone.local(2026, 7, 30, 12, 0, 0),
      updated_at: Time.zone.local(2026, 7, 30, 12, 0, 0)
    }
  end

  def article_attributes(title:, slug:, **overrides)
    now = Time.zone.local(2026, 7, 30, 12, 0, 0)
    {
      title:,
      slug:,
      summary: "#{title}の概要",
      published: true,
      published_at: now,
      recommended_areas: "umeda",
      recommended_order: 0,
      created_at: now,
      updated_at: now
    }.merge(overrides)
  end
end
