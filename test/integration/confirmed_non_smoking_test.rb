require "test_helper"

class ConfirmedNonSmokingTest < ActionDispatch::IntegrationTest
  setup do
    config = Rails.root.join("app/controllers/admin/base_controller.rb").read
    credentials = config.match(/name: "([^"]+)", password: "([^"]+)"/)
    @headers = { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(credentials[1], credentials[2]) }
    Geocoder.configure(lookup: :test)
    Geocoder::Lookup::Test.set_default_stub([])
    @shop = Shop.create!(name: "禁煙確認テスト", address: "大阪市北区梅田1-2-3", genre: "カフェ", last_confirmed_on: Date.current, approved: true, smoking_area: :all_smoking, smoking_type: :both_ok, smoking_area_2: :separated, smoking_type_2: :electronic_only, smoking_unverified: true)
  end

  test "only resolved non smoking reasons display a non smoking shop" do
    [ "禁煙になった", "禁煙店になった", "禁煙店だった" ].each do |reason|
      @shop.update!(approved: true, on_hold: false)
      report = @shop.shop_reports.create!(reason: reason)
      assert_not @shop.confirmed_non_smoking?
      patch "/panel_8m4k/shop_reports/#{report.id}/resolve", headers: @headers
      assert_response :redirect
      assert report.reload.resolved?
      assert @shop.reload.confirmed_non_smoking?
      assert_not @shop.approved?
      assert_public_non_smoking
      get root_path
      assert_select ".shop-card__titleLink", text: @shop.name
      assert_select ".shop-card .smoking-badge--non-smoking", text: "禁煙店"
    end
  end

  test "other resolved reasons and rejected non smoking reports do not mark non smoking" do
    [ "閉店した", "場所が違う", "店名が違う", "その他", "一部禁煙になった" ].each do |reason|
      @shop.update!(approved: true, on_hold: false)
      report = @shop.shop_reports.create!(reason: reason)
      patch "/panel_8m4k/shop_reports/#{report.id}/resolve", headers: @headers
      assert_not @shop.reload.confirmed_non_smoking?, reason
      get shop_path(@shop)
      assert_select ".smoking-badge--non-smoking", count: 0
    end
    report = @shop.shop_reports.create!(reason: "禁煙店だった")
    patch "/panel_8m4k/shop_reports/#{report.id}/reject", headers: @headers
    assert report.reload.rejected?
    assert_not @shop.reload.confirmed_non_smoking?
  end

  test "approved non smoking status edits also update the public page and article card" do
    %w[was_non_smoking became_non_smoking].each do |reason|
      @shop.update!(approved: true, on_hold: false)
      request = @shop.shop_edit_requests.create!(status_report_type: reason)
      assert_not @shop.confirmed_non_smoking?
      patch "/panel_8m4k/shop_edit_requests/#{request.id}/approve", headers: @headers
      assert_response :redirect
      assert request.reload.approved?
      assert @shop.reload.confirmed_non_smoking?
      assert_public_non_smoking
      article = Article.create!(title: "禁煙店舗の確認", slug: "non-smoking-#{reason}", published: true, published_at: Time.current, body: "[shop id=#{@shop.id}]")
      get article_path(article)
      assert_response :success
      assert_select ".refine-article-shop-card .smoking-badge--non-smoking", text: "禁煙店"
      assert_select ".refine-article-shop-card .smoking-badge--seat", count: 0
      assert_select ".refine-article-shop-card .smoking-badge--heated", count: 0
    end
  end

  test "legacy generic holds recognize the latest resolved report and stop after restored approval" do
    @shop.update!(approved: false, on_hold: true, hold_reason: "通報対応")
    @shop.shop_reports.create!(reason: "禁煙になった", status: :resolved, updated_at: 1.day.ago)
    assert @shop.confirmed_non_smoking?
    assert_public_non_smoking
    @shop.shop_reports.create!(reason: "閉店した", status: :resolved)
    assert_not @shop.confirmed_non_smoking?
    @shop.update!(hold_reason: "became_non_smoking")
    patch "/panel_8m4k/shops/#{@shop.id}/approve", headers: @headers
    assert_response :redirect
    assert_not @shop.reload.confirmed_non_smoking?
    get shop_path(@shop)
    assert_select ".smoking-badge--non-smoking", count: 0
  end

  test "confirmed non smoking shops come last for every sort and appear in name search" do
    @shop.update!(name: "掲載互換 禁煙", approved: false, on_hold: true, hold_reason: "became_non_smoking")
    smoking = Shop.create!(name: "掲載互換 喫煙", address: "大阪市北区梅田1-2-4", genre: "カフェ", approved: true, smoking_area: :all_smoking, smoking_type: :both_ok, last_confirmed_on: 1.year.ago.to_date)
    %w[recommended rating reviews_count newest].each do |sort|
      get root_path, params: { q: "掲載互換", sort: sort }
      assert_response :success
      assert_equal [ smoking.name, @shop.name ], css_select(".shop-card__titleLink").map(&:text)
      assert_select ".shop-card:last-child .smoking-badge--non-smoking", text: "禁煙店"
      assert_includes response.body, "この店舗では喫煙できません"
    end
    get root_path, params: { q: @shop.name }
    assert_select ".shop-card__titleLink", text: @shop.name
  end

  test "non smoking shops stay out of smoking filters open now search and map" do
    @shop.update!(approved: false, on_hold: true, hold_reason: "was_non_smoking", latitude: 34.7, longitude: 135.5)
    [ { smoking_area: "all_smoking" }, { smoking_type: "both_ok" }, { open_now: "1" }, { open_now_only: "1" } ].each do |filters|
      get root_path, params: filters.merge(q: @shop.name)
      assert_response :success
      assert_select ".shop-card__titleLink", text: @shop.name, count: 0
    end
    get umeda_smoking_path("all_smoking"), params: { q: @shop.name }
    assert_select ".shop-card__titleLink", text: @shop.name, count: 0
    get map_path
    assert_response :success
    assert_not_includes response.body, %Q("id":#{@shop.id},)
  end

  test "legacy resolved non smoking holds are listed but other holds and pending shops are excluded" do
    @shop.update!(approved: false, on_hold: true, hold_reason: "通報対応")
    @shop.shop_reports.create!(reason: "禁煙になった", status: :resolved)
    assert_includes Shop.public_listing, @shop
    get root_path, params: { q: @shop.name }
    assert_select ".shop-card .smoking-badge--non-smoking", text: "禁煙店"
    @shop.shop_reports.create!(reason: "閉店した", status: :resolved)
    assert_not_includes Shop.public_listing, @shop
    @shop.update!(on_hold: false)
    assert_not_includes Shop.public_listing, @shop
  end

  test "non smoking ordering is applied before pagination" do
    @shop.update!(name: "掲載ページ 禁煙", approved: false, on_hold: true, hold_reason: "became_non_smoking")
    30.times do |i|
      Shop.create!(name: "掲載ページ 喫煙#{i}", address: "大阪市北区梅田1-#{i+10}", genre: "カフェ", approved: true, smoking_area: :all_smoking, smoking_type: :both_ok, last_confirmed_on: 1.year.ago.to_date)
    end
    get root_path, params: { q: "掲載ページ", per: 30 }
    assert_select ".shop-card__titleLink", count: 30
    assert_select ".shop-card__titleLink", text: @shop.name, count: 0
    get root_path, params: { q: "掲載ページ", per: 30, page: 2 }
    assert_equal [ @shop.name ], css_select(".shop-card__titleLink").map(&:text)
  end

  private

  def assert_public_non_smoking
    get shop_path(@shop)
    assert_response :success
    assert_select ".shop-show__badges .smoking-badge--non-smoking", text: "禁煙店"
    assert_select ".shop-show__badges .smoking-badge--seat", count: 0
    assert_select ".shop-show__badges .smoking-badge--both", count: 0
    assert_select ".shop-show__badges .smoking-badge--heated", count: 0
    assert_select ".refine-non-smoking-notice h2", text: "この店舗は禁煙店です"
    assert_select ".ss-pending", count: 0
    assert_select "title", text: /禁煙店/
    data = Nokogiri::HTML(response.body).css('script[type="application/ld+json"]').map { |node| JSON.parse(node.text) }
    restaurant = data.find { |item| item["@type"] == "Restaurant" }
    assert_equal false, restaurant.fetch("smokingAllowed")
  end
end
