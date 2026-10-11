require "test_helper"

class RefineCompatibilityTest < ActionDispatch::IntegrationTest
  UA = { "User-Agent" => "Mozilla/5.0 Chrome/138.0 Safari/537.36" }.freeze
  setup do
    Geocoder.configure(lookup: :test)
    Geocoder::Lookup::Test.set_default_stub([])
    Shop.update_all(approved: false, on_hold: false)
    Article.update_all(published: false)
    @shop = make_shop
  end

  test "database count, all smoking states and secondary conditions use the theme" do
    %w[all_smoking separated unknown].product(%w[both_ok electronic_only paper_only unknown]).each do |area, type|
      make_shop(smoking_area: Shop.smoking_areas[area], smoking_type: Shop.smoking_types[type])
    end
    get "/", headers: UA
    assert_response :success
    assert_select "body.suelog-refine"
    assert_select ".hero__meta-bar", text: /掲載13件/
    %w[seat room both heated paper unknown].each { |state| assert_select ".smoking-badge--#{state}" }
    @shop.update_columns(smoking_area_2: 0, smoking_type_2: 1)
    get shop_path(@shop), headers: UA
    assert_select ".shop-show__badges .smoking-badge--room"
    assert_select ".shop-show__badges .smoking-badge--heated"
    assert_select 'script[type="application/ld+json"]'
    assert_select 'link[rel="canonical"]'
  end

  test "business hours and smoking verification have distinct labels and states" do
    @shop.update!(opening_hours_json: { "sunday" => { "open" => "11:00", "close" => "13:00", "closed" => false } }, smoking_unverified: true)
    travel_to Time.zone.local(2026, 10, 11, 12, 0) do
      assert @shop.open_now?
      get root_path, params: { q: @shop.name }
      assert_select ".shop-card .refine-business-status--open", text: /営業中/
      assert_select ".shop-card .refine-verification--unverified", text: /喫煙情報 未確認/
      get shop_path(@shop)
      assert_select ".shop-show__badges .refine-business-status--open", text: /営業中/
      assert_select ".shop-show__badges .refine-verification--unverified"
    end
    @shop.update!(smoking_unverified: false)
    travel_to Time.zone.local(2026, 10, 11, 15, 0) do
      assert_not @shop.open_now?
      get root_path, params: { q: @shop.name }
      assert_select ".shop-card .refine-business-status--outside", text: /営業時間外/
      assert_select ".shop-card .refine-verification--verified", text: /喫煙情報 確認済み/
      assert_select ".badge--closed-inline", count: 0
      get shop_path(@shop)
      assert_select ".shop-show__badges .refine-business-status--outside", text: /営業時間外/
      assert_select ".shop-show__badges .refine-verification--verified"
    end
  end

  test "missing routes, station, shops and reviews return actual 404" do
    [ "/umeda/anything", "/umeda/genre/not-a-genre", "/umeda/station/not-a-station", "/shops/999999999", "/shops/999999999/reviews/new", "/shops/999999999/track_click", "/articles/missing/track_shop_click", "/reviews/999999999/edit", "/shops/999999999/shop_reports/new", "/articles/missing" ].each do |path|
      get path, headers: UA
      assert_response :not_found, path
    end
    get "/shops", headers: UA
    assert_response :moved_permanently
    assert_redirected_to "/"
  end

  test "registration retains nested multipart fields and 24:00 quarter hours" do
    get "/shops/new", headers: UA
    assert_response :success
    assert_select 'form[action="/shops"][method="post"][enctype="multipart/form-data"]'
    assert_select '[name="shop[name]"]'
    assert_select 'option[value="24:00"]'
    assert_select 'option[value="23:45"]'
    assert_select 'input[type="file"]', count: 4
    assert_difference("Shop.count", 1) do
      post "/shops", params: { shop: { name: "\u767B\u9332\u78BA\u8A8D", address: "\u5927\u962A\u5E02\u5317\u533A\u6885\u75302", genre: "\u5C45\u9152\u5C4B", last_confirmed_on: Date.current, smoking_area: "all_smoking", smoking_type: "both_ok", opening_hours_text: "\u6708 18:00-24:00" } }, headers: UA
    end
    assert_response :redirect
    assert_not Shop.order(:id).last.approved?
    assert_equal "all_smoking", Shop.order(:id).last.smoking_area
  end

  test "invalid registration and duplicate phone keep validation and input" do
    post "/shops", params: { shop: { name: "\u6B8B\u308B\u540D\u524D" } }, headers: UA
    assert_response :unprocessable_entity
    assert_select 'input[name="shop[name]"][value="残る名前"]'
    @shop.update_columns(phone: "06-1234-5678", normalized_phone: "0612345678")
    assert_no_difference("Shop.count") do
      post "/shops", params: { shop: { name: "\u91CD\u8907", phone: "06-1234-5678" } }, headers: UA
    end
    assert_response :unprocessable_entity
    assert_select 'a[href*="possible_duplicates"]'
    get "/shops/possible_duplicates", params: { phone: "06-1234-5678" }, headers: UA
    assert_response :success
  end

  test "contact saves only valid nested input and completes locally" do
    post "/contact", params: { contact_message: { name: "\u78BA\u8A8D", email: "invalid", subject: "\u8CEA\u554F", body: "\u5185\u5BB9" } }, headers: UA
    assert_response :unprocessable_entity
    assert_difference("ContactMessage.count", 1) do
      post "/contact", params: { contact_message: { name: "\u78BA\u8A8D", email: "preview@example.test", subject: "\u8CEA\u554F", body: "\u5185\u5BB9" } }, headers: UA
    end
    assert_redirected_to "/contact/done"
    follow_redirect!; assert_response :success
  end

  test "reviews save pending, enforce one per IP and owner association for editing" do
    assert_difference("Review.count", 1) do
      post shop_reviews_path(@shop), params: { review: { rating: 4, comment: "\u30ED\u30FC\u30AB\u30EB\u6295\u7A3F", author_name: "\u78BA\u8A8D\u8005" } }, headers: UA
    end
    review = @shop.reviews.order(:id).last
    assert_not review.approved?
    assert_equal @shop.id, review.shop_id
    assert_no_difference("Review.count") do
      post shop_reviews_path(@shop), params: { review: { rating: 5 } }, headers: UA
    end
    get edit_review_path(review), headers: UA
    assert_response :success
    patch review_path(review), params: { review: { rating: 5, comment: "\u672C\u4EBA\u4FEE\u6B63" } }, headers: UA
    assert_response :redirect
    assert_equal "\u672C\u4EBA\u4FEE\u6B63", review.reload.comment
    get edit_review_path(review), headers: UA.merge("REMOTE_ADDR" => "192.0.2.10")
    assert_response :redirect
    assert_redirected_to shop_path(@shop, anchor: "review-form")
  end

  test "shop edits and both reports use existing pending approval workflows" do
    get new_shop_shop_edit_request_path(@shop), headers: UA
    assert_response :success
    assert_select '[name="shop_edit_request[proposed_smoking_area]"]'
    assert_select 'option[value="24:00"]'
    assert_difference("ShopEditRequest.count", 1) do
      post shop_shop_edit_requests_path(@shop), params: { shop_edit_request: { proposed_name: "\u5909\u66F4\u4F9D\u983C", proposed_smoking_area: "area_separated", proposed_smoking_type: "type_electronic_only" } }, headers: UA
    end
    assert_response :redirect
    assert @shop.shop_edit_requests.last.pending?
    assert_equal "\u691C\u8A3C\u5E97\u8217", @shop.reload.name
    assert_difference("ShopReport.count", 1) do
      post shop_shop_reports_path(@shop), params: { shop_report: { reason: "\u7981\u7159\u306B\u306A\u3063\u305F", detail: "\u78BA\u8A8D\u4F9D\u983C" } }, headers: UA
    end
    review = @shop.reviews.create!(rating: 3, ip_hash: "report-fixture", approved: true)
    assert_difference("ReviewReport.count", 1) do
      post review_review_reports_path(review), params: { review_report: { reason: "\u4E8B\u5B9F\u3068\u7570\u306A\u308B" } }, headers: UA
    end
    assert_response :redirect
  end

  test "phone map and booking conversions are recorded before redirect with unsafe targets rejected" do
    { "phone_click" => "tel:0612345678", "map_click" => "https://www.google.com/maps?q=local", "affiliate_click" => "https://tabelog.com/osaka/local-preview/" }.each do |kind, target|
      assert_difference("ShopClick.count", 1) do
        get track_click_shop_path(@shop), params: { kind: kind, target_url: target }, headers: UA
      end
      assert_response :redirect
      assert_equal target, response.location
    end
    assert_no_difference("ShopClick.count") do
      get track_click_shop_path(@shop), params: { kind: "affiliate_click", target_url: "javascript:alert(1)" }, headers: UA
    end
    assert_redirected_to shop_path(@shop)
  end

  test "article cards, CTA, related links and active local affiliate ads retain real rendering" do
    ad = AffiliateAd.create!(key: "preview-ad", active: true, url: "/terms", image_path: "refine/shop-bar.jpg")
    article = Article.create!(title: "\u691C\u8A3C\u8A18\u4E8B", slug: "refine-check", published: true, published_at: 1.day.ago)
    article.body = "<h2>お店の紹介</h2><p>[shop id=#{@shop.id}]</p><p>[ad key=preview-ad]</p><p>[article-cta]</p>"
    article.save!
    get article_path(article), headers: UA
    assert_response :success
    assert_select ".refine-article-shop-card .smoking-badge--seat"
    assert_select 'a[href="/terms"][rel*="sponsored"] img[alt="広告"]'
    assert_select 'a[href*="track_shop_click"]'
    assert_difference("ShopClick.count", 1) do
      get track_shop_click_article_path(article), params: { shop_id: @shop.id }, headers: UA
    end
    assert_redirected_to shop_path(@shop)
    ad.update!(active: false)
    get article_path(article), headers: UA
    assert_select 'a[href="/terms"][rel*="sponsored"]', count: 0
  end

  test "all destination pages retain themed layout and map server data" do
    [ "/umeda", "/namba", "/map", "/articles", "/terms", "/privacy", "/contact", new_shop_shop_report_path(@shop) ].each do |path|
      get path, headers: UA
      assert_response :success, path
      assert_select "body.suelog-refine"
      assert_select 'link[href*="refine"]'
    end
  end

  test "CSRF rejects missing tokens and accepts the Rails form token" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    get "/contact", headers: UA
    token = Nokogiri::HTML(response.body).at_css('input[name="authenticity_token"]')["value"]
    payload = { contact_message: { name: "CSRF\u78BA\u8A8D", email: "preview@example.test", subject: "\u78BA\u8A8D", body: "\u30ED\u30FC\u30AB\u30EB" } }
    assert_no_difference("ContactMessage.count") { post "/contact", params: payload, headers: UA }
    assert_response :unprocessable_entity
    assert_difference("ContactMessage.count", 1) { post "/contact", params: payload.merge(authenticity_token: token), headers: UA }
    assert_redirected_to "/contact/done"
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  test "review uploads preserve categories and reject unsupported file types" do
    file = Rack::Test::UploadedFile.new(Rails.root.join("app/assets/images/refine/shop-yakitori.jpg"), "image/jpeg")
    post shop_reviews_path(@shop), params: { review: { rating: 4, food_photos: [ file ] } }, headers: UA
    assert_response :redirect
    review = @shop.reviews.order(:id).last
    assert_equal 1, review.food_photos.count
    assert_not review.approved?
    other_shop = make_shop
    Tempfile.create([ "unsupported-preview", ".pdf" ]) do |temp|
      temp.write("%PDF-1.7\nUnsupported image test")
      temp.flush
      invalid = Rack::Test::UploadedFile.new(temp.path, "application/pdf")
      assert_no_difference("Review.count") do
        post shop_reviews_path(other_shop), params: { review: { rating: 4, menu_photos: [ invalid ] } }, headers: UA
      end
      assert_response :unprocessable_entity
    end
  end

  test "old split-page links redirect to verified section anchors" do
    %w[photos reviews access booking].each do |section|
      get "/shops/#{@shop.id}/#{section}", headers: UA
      assert_redirected_to "/shops/#{@shop.id}##{section}"
    end
    @shop.update_columns(tabelog_url: "https://tabelog.com/osaka/local-preview/")
    get shop_path(@shop), headers: UA
    %w[photos reviews access booking review-form].each { |id| assert_select "##{id}" }
    assert_select '.shop-show__stickyCta a[href*="track_click"]'
  end

  private
  def make_shop(**overrides)
    now = Time.current
    row = { name: "\u691C\u8A3C\u5E97\u8217", address: "\u5927\u962A\u5E02\u5317\u533A\u6885\u75301-1", area: "\u6885\u7530", genre: "\u5C45\u9152\u5C4B", nearest_station: "\u6885\u7530\u99C5", approved: true, rejected: false, on_hold: false, smoking_area: 1, smoking_type: 0, opening_hours_json: {}, import_metadata: {}, seat_type_tags: [], last_confirmed_on: Date.current, latitude: 34.7025, longitude: 135.4959, created_at: now, updated_at: now }.merge(overrides)
    Shop.find(Shop.insert_all!([ row ], returning: [ :id ]).rows.first.first)
  end
end
