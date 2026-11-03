require "test_helper"

class RefineAdminCompatibilityTest < ActionDispatch::IntegrationTest
  setup do
    # Authenticate only against the isolated application's existing configuration.
    # Do not embed credentials in the migration package or test output.
    config = Rails.root.join("app/controllers/admin/base_controller.rb").read
    credentials = config.match(/name: "([^"]+)", password: "([^"]+)"/)
    raise "Admin authentication configuration changed" unless credentials
    @headers = { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(credentials[1], credentials[2]) }
    Geocoder.configure(lookup: :test)
    Geocoder::Lookup::Test.set_default_stub([])
    @shop = Shop.create!(name: "\u7BA1\u7406\u691C\u8A3C\u5E97\u8217", address: "\u5927\u962A\u5E02\u5317\u533A\u6885\u75301-20", genre: "\u5C45\u9152\u5C4B", last_confirmed_on: Date.current, smoking_area: :all_smoking, smoking_type: :both_ok, smoking_unverified: true, approved: true)
    @review = @shop.reviews.create!(rating: 4, ip_hash: "admin-compatibility", comment: "\u627F\u8A8D\u691C\u8A3C", approved: false)
    @edit = @shop.shop_edit_requests.create!(proposed_name: "\u7BA1\u7406\u4FEE\u6B63\u5E97\u8217", proposed_smoking_area: "area_separated", proposed_smoking_type: "type_electronic_only")
    @report = @shop.shop_reports.create!(reason: "\u7981\u7159\u306B\u306A\u3063\u305F", detail: "\u30ED\u30FC\u30AB\u30EB\u691C\u8A3C", status: :pending)
    @contact = ContactMessage.create!(name: "\u78BA\u8A8D\u8005", email: "local@example.test", subject: "\u7BA1\u7406\u753B\u9762\u691C\u8A3C", body: "\u30ED\u30FC\u30AB\u30EB\u5C02\u7528")
    @article = Article.create!(title: "\u7BA1\u7406\u691C\u8A3C\u8A18\u4E8B", slug: "admin-compatibility", published: false)
    @ad = AffiliateAd.create!(key: "admin-compatibility", url: "/terms", image_path: "refine/shop-bar.jpg", active: true)
    @user = SubAdminUser.create!(name: "\u30ED\u30FC\u30AB\u30EB\u78BA\u8A8D\u8005", login_id: "refine-local-admin", password: "local-test-only-12345", active: true, permissions: [ "smoking_check" ])
  end

  test "non tabelog staged search queues work protects URLs and rejects listing URLs" do
    %w[hotpepper gurunavi].each do |provider|
      assert_enqueued_with(job: RestaurantUrlSearchJob) do
        post search_provider_url_admin_shop_path(@shop), headers: @headers, params: { provider: provider }
      end
      assert_response :see_other
      run = RestaurantUrlSearchRun.find_by!(shop: @shop, provider: provider)
      assert_equal "pending", run.state
      assert_no_enqueued_jobs(only: RestaurantUrlSearchJob) do
        post search_provider_url_admin_shop_path(@shop), headers: @headers, params: { provider: provider }
      end
      @shop.update!("#{provider}_url" => "https://example.test/confirmed/")
      assert_no_enqueued_jobs(only: RestaurantUrlSearchJob) do
        post search_provider_url_admin_shop_path(@shop), headers: @headers, params: { provider: provider }
      end
      assert_equal "https://example.test/confirmed/", @shop.reload.public_send("#{provider}_url")
    end
    post search_provider_url_admin_shop_path(@shop), headers: @headers, params: { provider: "tabelog" }
    assert_response :unprocessable_entity
    patch admin_shop_path(@shop), headers: @headers.merge("ACCEPT"=>"application/json"), params: { inline_hotpepper_update: "1", shop: { hotpepper_url: "https://www.hotpepper.jp/SA23/" } }
    assert_response :unprocessable_entity
    assert_equal "https://example.test/confirmed/", @shop.reload.hotpepper_url
    get admin_shops_path(status: "tabelog_missing", q: @shop.name), headers: @headers
    assert_select "button", text: "段階検索・店舗照合", count: 0
    query = URI.decode_www_form(URI.parse(css_select("a[data-tabelog-search-shop-id]").first["href"]).query).to_h["q"]
    assert_equal [@shop.name, @shop.address, "食べログ site:tabelog.com"].join(" "), query
  end

  test "not found provider lists restore shops to the missing queue without changing other providers" do
    %w[tabelog hotpepper gurunavi].each do |provider|
      @shop.update!(tabelog_url: "https://tabelog.com/test/", tabelog_affiliate_url: "https://affiliate.example/tabelog", hotpepper_url: "https://www.hotpepper.jp/strJ001234567/", hotpepper_affiliate_url: "https://affiliate.example/hotpepper", gurunavi_url: "https://r.gnavi.co.jp/abcd123/", gurunavi_affiliate_url: "https://affiliate.example/gurunavi", "hide_#{provider}_booking_button" => true)
      patch public_send("mark_#{provider}_not_found_admin_shop_path", @shop), headers: @headers.merge("ACCEPT" => "application/json")
      assert_response :success
      get admin_shops_path(status: "#{provider}_not_found", q: @shop.name), headers: @headers
      assert_response :success
      assert_select "[data-shop-row-id='#{@shop.id}'] button", text: "未設定に戻す", count: 1
      assert_select "input[type='url']", count: 0
      before = @shop.reload.attributes
      patch restore_affiliate_not_found_admin_shop_path(@shop), headers: @headers, params: { provider: provider, q: @shop.name, per: 50, page: 1 }
      assert_response :see_other
      @shop.reload
      assert_nil @shop.public_send("#{provider}_url")
      assert_nil @shop.public_send("#{provider}_affiliate_url")
      assert @shop.public_send("hide_#{provider}_booking_button?")
      (%w[tabelog hotpepper gurunavi] - [provider]).each do |other|
        assert_equal before["#{other}_url"], @shop.public_send("#{other}_url")
        assert_equal before["#{other}_affiliate_url"], @shop.public_send("#{other}_affiliate_url")
      end
      if provider == "tabelog"
        assert_nil @shop.tabelog_match_method
        assert_nil @shop.tabelog_matched_at
      end
      get admin_shops_path(status: "#{provider}_not_found", q: @shop.name, format: :json), headers: @headers
      assert_equal 0, response.parsed_body["total_count"]
      get admin_shops_path(status: "#{provider}_missing", q: @shop.name, format: :json), headers: @headers
      assert_equal 1, response.parsed_body["total_count"]
      @shop.update!("#{provider}_url" => "https://example.test/new-value/")
      patch restore_affiliate_not_found_admin_shop_path(@shop), headers: @headers, params: { provider: provider }
      assert_response :unprocessable_entity
      assert_equal "https://example.test/new-value/", @shop.reload.public_send("#{provider}_url")
    end
    patch restore_affiliate_not_found_admin_shop_path(@shop), headers: @headers, params: { provider: "unknown" }
    assert_response :unprocessable_entity
  end

  test "affiliate queues and configured lists sort by human page views rather than click count" do
    high = @shop.dup
    high.name = "アクセス順検証 多"
    high.save!
    @shop.update!(name: "アクセス順検証 少")
    zero = @shop.dup
    zero.name = "アクセス順検証 ゼロ"
    zero.save!
    3.times { PageView.create!(shop: high, path: "/shops/#{high.id}", is_bot: false) }
    PageView.create!(shop: @shop, path: "/shops/#{@shop.id}", is_bot: nil)
    6.times { PageView.create!(shop: zero, path: "/shops/#{zero.id}", is_bot: true) }
    5.times { @shop.shop_clicks.create!(kind: "affiliate_click") }
    %w[tabelog hotpepper gurunavi].each do |provider|
      %w[missing configured].each do |state|
        attrs = state == "missing" ? { "#{provider}_url" => nil, "#{provider}_affiliate_url" => nil } : { "#{provider}_url" => "https://example.test/store/", "#{provider}_affiliate_url" => "https://affiliate.example/store" }
        Shop.where(id: [high.id, @shop.id, zero.id]).update_all(attrs)
        get admin_shops_path(status: "#{provider}_#{state}", q: "アクセス順検証", per: 2), headers: @headers
        assert_response :success
        assert_equal [high.id.to_s, @shop.id.to_s], css_select("[data-shop-row-id]").map { |row| row["data-shop-row-id"] }
        assert_equal ["3", "1"], css_select("[data-affiliate-access-count]").map { |cell| cell.text.strip }
        get admin_shops_path(status: "#{provider}_#{state}", q: "アクセス順検証", per: 2, format: :json, visible_ids: [high.id]), headers: @headers
        assert_response :success
        assert_equal 3, response.parsed_body["total_count"]
        rows = Nokogiri::HTML.fragment(response.parsed_body["rows_html"])
        assert_equal [@shop.id.to_s], rows.css("[data-shop-row-id]").map { |row| row["data-shop-row-id"] }
        get admin_shops_path(status: "#{provider}_#{state}", q: "アクセス順検証", per: 2, page: 2), headers: @headers
        assert_equal [zero.id.to_s], css_select("[data-shop-row-id]").map { |row| row["data-shop-row-id"] }
      end
    end
  end

  test "global provider stop overrides every shop while preserving individual preferences" do
    BookingProviderSetting.delete_all
    @shop.update!(tabelog_url: "https://tabelog.com/test/", tabelog_affiliate_url: "https://affiliate.example/tabelog", hotpepper_url: "https://www.hotpepper.jp/strJ001234567/", hotpepper_affiliate_url: "https://affiliate.example/hotpepper")
    other = @shop.dup
    other.name = "一括表示確認店舗"
    other.save!
    get admin_shops_path(status: "tabelog_missing"), headers: @headers
    assert_select "[data-global-booking-provider='tabelog'] input[type='submit'][value='食べログを全店舗で非表示']", count: 1
    patch global_booking_visibility_admin_shops_path, headers: @headers, params: { provider: "tabelog", hidden: "1" }
    assert_response :see_other
    [@shop, other].each do |shop|
      get shop_path(shop)
      assert_select "a.shop-show__cvPrimary--tabelog", count: 0
      assert_select "a.shop-show__cvPrimary--hotpepper", minimum: 1
      assert_equal "no-store", response.headers["Cache-Control"]
    end
    get track_click_shop_path(@shop, kind: "affiliate_click", target_url: @shop.tabelog_affiliate_url)
    assert_redirected_to shop_path(@shop)
    assert_not @shop.reload.hide_tabelog_booking_button?
    assert_equal "https://affiliate.example/tabelog", @shop.tabelog_affiliate_url
    other.update!(hide_tabelog_booking_button: true)
    patch global_booking_visibility_admin_shops_path, headers: @headers, params: { provider: "tabelog", hidden: "0" }
    get shop_path(@shop)
    assert_select "a.shop-show__cvPrimary--tabelog", minimum: 1
    get shop_path(other)
    assert_select "a.shop-show__cvPrimary--tabelog", count: 0
    patch global_booking_visibility_admin_shops_path, headers: @headers, params: { provider: "all", hidden: "1" }
    get shop_path(@shop)
    assert_select "a.shop-show__cvPrimary--hotpepper", count: 0
    assert_select "a.shop-show__cvPrimary--tabelog", count: 0
    patch global_booking_visibility_admin_shops_path, headers: @headers, params: { provider: "invalid", hidden: "1" }
    assert_response :unprocessable_entity
    patch global_booking_visibility_admin_shops_path, headers: @headers, params: { provider: "all", hidden: "0" }
    get shop_path(@shop)
    assert_select "a.shop-show__cvPrimary--hotpepper", minimum: 1
  end

  test "gurunavi saves source URLs separately and refills the unregistered queue" do
    get admin_shops_path(status: "gurunavi_missing", q: @shop.name), headers: @headers
    assert_response :success
    assert_select "input[name='shop[gurunavi_url]']", count: 1
    assert_includes response.body, "ぐるなびなし"
    patch admin_shop_path(@shop), headers: @headers.merge("ACCEPT" => "application/json"), params: { inline_gurunavi_update: "1", shop: { gurunavi_url: "https://r.gnavi.co.jp/abcd1234/" } }
    assert_response :success
    assert_equal "https://r.gnavi.co.jp/abcd1234/", @shop.reload.gurunavi_url
    assert_equal GurunaviAffiliateUrlBuilder.call(@shop.gurunavi_url), @shop.gurunavi_affiliate_url
    get admin_shops_path(status: "gurunavi_missing", q: @shop.name, format: :json), headers: @headers
    assert_response :success
    assert_equal 0, response.parsed_body["total_count"]
    get admin_shops_path(status: "gurunavi_configured", q: @shop.name), headers: @headers
    assert_response :success
    assert_includes response.body, "アフィリエイト設定済み"
    get shop_path(@shop)
    assert_select "a.shop-show__cvPrimary--gurunavi", minimum: 1
    get track_click_shop_path(@shop, kind: "affiliate_click", target_url: @shop.gurunavi_affiliate_url)
    assert_redirected_to @shop.gurunavi_affiliate_url
    patch admin_shop_path(@shop), headers: @headers.merge("ACCEPT" => "application/json"), params: { inline_gurunavi_update: "1", shop: { gurunavi_url: "https://r.gnavi.co.jp.evil.test/abcd/" } }
    assert_response :unprocessable_entity
    assert_equal "https://r.gnavi.co.jp/abcd1234/", @shop.reload.gurunavi_url
    patch booking_visibility_admin_shop_path(@shop), headers: @headers.merge("ACCEPT" => "application/json"), params: { provider: "gurunavi", hidden: "1" }
    assert_response :success
    assert @shop.reload.hide_gurunavi_booking_button?
    @shop.update!(gurunavi_affiliate_url: "https://affiliate.example/gurunavi")
    get shop_path(@shop)
    assert_select "a.shop-show__cvPrimary--gurunavi", count: 0
    @shop.update!(hide_gurunavi_booking_button: false)
    get shop_path(@shop)
    assert_select "a.shop-show__cvPrimary--gurunavi", minimum: 1
    @shop.update!(gurunavi_url: "https://r.gnavi.co.jp/next123/")
    assert_nil @shop.reload.gurunavi_affiliate_url
    patch mark_gurunavi_not_found_admin_shop_path(@shop), headers: @headers.merge("ACCEPT" => "application/json")
    assert_response :success
    get admin_shops_path(status: "gurunavi_missing", q: @shop.name, format: :json), headers: @headers
    assert_equal 0, response.parsed_body["total_count"]
    get admin_shops_path(status: "gurunavi_configured", q: @shop.name, format: :json), headers: @headers
    assert_equal 0, response.parsed_body["total_count"]
  end

  test "provider booking buttons hide independently without deleting URLs and can be restored" do
    @shop.update!(tabelog_url: "https://tabelog.com/test/", tabelog_affiliate_url: "https://affiliate.example/tabelog", hotpepper_url: "https://www.hotpepper.jp/strJ001234567/", hotpepper_affiliate_url: "https://affiliate.example/hotpepper")
    get shop_path(@shop)
    assert_select "a.shop-show__cvPrimary--tabelog", minimum: 1
    assert_select "a.shop-show__cvPrimary--hotpepper", minimum: 1
    patch booking_visibility_admin_shop_path(@shop), headers: @headers.merge("ACCEPT" => "application/json"), params: { provider: "tabelog", hidden: "1" }
    assert_response :success
    assert_equal true, response.parsed_body["hidden"]
    get shop_path(@shop)
    assert_select "a.shop-show__cvPrimary--tabelog", count: 0
    assert_select "a.shop-show__cvPrimary--hotpepper", minimum: 1
    patch booking_visibility_admin_shop_path(@shop), headers: @headers.merge("ACCEPT" => "application/json"), params: { provider: "hotpepper", hidden: "1" }
    assert_response :success
    get shop_path(@shop)
    assert_select "a.shop-show__cvPrimary--hotpepper", count: 0
    @shop.reload
    assert_equal "https://affiliate.example/tabelog", @shop.tabelog_affiliate_url
    assert_equal "https://affiliate.example/hotpepper", @shop.hotpepper_affiliate_url
    patch booking_visibility_admin_shop_path(@shop), headers: @headers.merge("ACCEPT" => "application/json"), params: { provider: "tabelog", hidden: "0" }
    get shop_path(@shop)
    assert_select "a.shop-show__cvPrimary--tabelog", minimum: 1
    assert_select "a.shop-show__cvPrimary--hotpepper", count: 0
  end

  test "admin editing persists booking visibility and rejects unknown providers" do
    get edit_admin_shop_path(@shop), headers: @headers
    assert_select "input[type='checkbox'][name='shop[hide_tabelog_booking_button]']", count: 1
    assert_select "input[type='checkbox'][name='shop[hide_hotpepper_booking_button]']", count: 1
    patch admin_shop_path(@shop), headers: @headers, params: { shop: { hide_tabelog_booking_button: "1", hide_hotpepper_booking_button: "1" } }
    assert_response :redirect
    assert @shop.reload.hide_tabelog_booking_button?
    assert @shop.hide_hotpepper_booking_button?
    patch booking_visibility_admin_shop_path(@shop), headers: @headers.merge("ACCEPT" => "application/json"), params: { provider: "custom", hidden: "0" }
    assert_response :unprocessable_entity
    assert @shop.reload.hide_tabelog_booking_button?
  end

  test "hotpepper not found leaves the work queue and never creates a public booking link" do
    @shop.update!(tabelog_url: "https://tabelog.com/test/", hotpepper_url: "https://www.hotpepper.jp/strJ001234567/", hotpepper_affiliate_url: "https://affiliate.example/test")
    assert_enqueued_with(job: AicooActivityDeliveryJob) do
      patch mark_hotpepper_not_found_admin_shop_path(@shop), headers: @headers.merge("ACCEPT" => "application/json")
    end
    assert_response :success
    assert_equal "ホットペッパーなしとして登録しました", response.parsed_body["message"]
    @shop.reload
    assert_match %r{\Ahttps://not-found\.local/}, @shop.hotpepper_url
    assert_nil @shop.hotpepper_affiliate_url
    assert_equal "https://tabelog.com/test/", @shop.tabelog_url
    get admin_shops_path(status: "hotpepper_missing"), headers: @headers
    assert_select "a[href^='/panel_8m4k/shops/#{@shop.id}/edit']", count: 0
    get shop_path(@shop)
    assert_select "a[href*='not-found.local']", count: 0
    assert_select "a[href*='affiliate.example']", count: 0
  end

  test "hotpepper setup searches saves generated affiliate and moves to configured independently" do
    previous = ENV["HOTPEPPER_AFFILIATE_URL_TEMPLATE"]
    ENV["HOTPEPPER_AFFILIATE_URL_TEMPLATE"] = "https://affiliate.example/redirect?target={url_encoded}"
    @shop.update!(tabelog_affiliate_url: "https://example.test/tabelog")
    get admin_shops_path(status: "hotpepper_missing"), headers: @headers
    assert_response :success
    assert_select "h1", text: "ホットペッパー アフィリエイト設定"
    assert_select "form[data-inline-tabelog-form] input[name='shop[hotpepper_url]']", count: 1
    assert_select "input[name='inline_hotpepper_update'][value='1']", count: 1
    assert_select "a[data-tabelog-search-shop-id]" do |links|
      assert_includes CGI.unescape(links.first["href"]), "site:www.hotpepper.jp"
    end
    assert_select "form[data-tabelog-not-found-form][data-booking-provider='ホットペッパー']", count: 1
    raw_url = "https://www.hotpepper.jp/strJ001234567/"
    assert_enqueued_with(job: AicooActivityDeliveryJob) do
      patch admin_shop_path(@shop), headers: @headers.merge("ACCEPT" => "application/json"), params: {
        inline_hotpepper_update: "1", shop: { hotpepper_url: raw_url, tabelog_affiliate_url: "https://ignored.test" }
      }
    end
    assert_response :success
    @shop.reload
    assert_equal raw_url, @shop.hotpepper_url
    assert_equal "https://affiliate.example/redirect?target=#{CGI.escape(raw_url)}", @shop.hotpepper_affiliate_url
    assert_equal "https://example.test/tabelog", @shop.tabelog_affiliate_url
    get admin_shops_path(status: "hotpepper_missing"), headers: @headers
    assert_select "a[href^='/panel_8m4k/shops/#{@shop.id}/edit']", count: 0
    get admin_shops_path(status: "hotpepper_configured"), headers: @headers
    assert_select "input[name='shop[hotpepper_url]']", count: 1
    get shop_path(@shop)
    assert_includes response.body, "affiliate.example"
    @shop.update!(hotpepper_url: "https://www.hotpepper.jp/strJ009999999/")
    assert_nil @shop.reload.hotpepper_affiliate_url
  ensure
    ENV["HOTPEPPER_AFFILIATE_URL_TEMPLATE"] = previous
  end

  test "hotpepper setup uses the supplied publisher by default and rejects other providers" do
    previous = ENV["HOTPEPPER_AFFILIATE_URL_TEMPLATE"]
    ENV.delete("HOTPEPPER_AFFILIATE_URL_TEMPLATE")
    patch admin_shop_path(@shop), headers: @headers.merge("ACCEPT" => "application/json"), params: {
      inline_hotpepper_update: "1", shop: { hotpepper_url: "https://www.hotpepper.jp/strJ001234567/" }
    }
    assert_response :success
    assert_includes @shop.reload.hotpepper_affiliate_url, "sid=3769275&pid=892606955"
    saved_url = @shop.hotpepper_url
    patch admin_shop_path(@shop), headers: @headers.merge("ACCEPT" => "application/json"), params: {
      inline_hotpepper_update: "1", shop: { hotpepper_url: "https://tabelog.com/test/" }
    }
    assert_response :unprocessable_entity
    assert_includes response.parsed_body["error"], "ホットペッパー"
    assert_equal saved_url, @shop.reload.hotpepper_url
  ensure
    ENV["HOTPEPPER_AFFILIATE_URL_TEMPLATE"] = previous
  end

  test "refill supplies the next matching row while preserving the visible rows" do
    4.times do |n|
      Shop.create!(name: "補充検証#{n}", address: "大阪市北区梅田#{n}", genre: "居酒屋", last_confirmed_on: Date.current,
        smoking_area: :all_smoking, smoking_type: :both_ok, approved: true)
    end
    candidates = Shop.where("name LIKE ?", "補充検証%").order(created_at: :desc).to_a
    patch admin_shop_path(candidates[0]), headers: @headers.merge("ACCEPT" => "application/json"), params: {
      inline_tabelog_update: "1", shop: { tabelog_url: "https://tabelog.com/test/" }
    }
    get admin_shops_path, headers: @headers.merge("ACCEPT" => "application/json"), params: {
      status: "tabelog_missing", q: "補充検証", per: 2, page: 1, visible_ids: [candidates[1].id]
    }
    assert_response :success
    data = response.parsed_body
    assert_equal 3, data["total_count"]
    assert_equal 2, data["total_pages"]
    rows = Nokogiri::HTML.fragment(data["rows_html"])
    assert_equal [candidates[2].id.to_s], rows.css("[data-shop-row-id]").map { |row| row["data-shop-row-id"] }
    assert rows.at_css("[data-inline-tabelog-form]")
    assert rows.at_css("[data-tabelog-search-shop-id]")
    assert_includes data["pagination_html"], "q="
    assert_equal "no-store", response.headers["Cache-Control"]
    assert data["csrf_token"].present?
  end

  test "stale CSRF tokens return a recoverable error and refreshed tokens allow saving" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    url = "https://tabelog.com/test/"
    patch admin_shop_path(@shop), headers: @headers.merge("ACCEPT" => "application/json", "X-CSRF-Token" => "stale"), params: {
      inline_tabelog_update: "1", shop: { tabelog_url: url }
    }
    assert_response :unprocessable_entity
    assert_equal "invalid_csrf", response.parsed_body["code"]
    assert_nil @shop.reload.tabelog_url
    get refresh_form_token_admin_shops_path, headers: @headers.merge("ACCEPT" => "application/json")
    assert_response :success
    token = response.parsed_body["csrf_token"]
    assert token.present?
    assert_equal "no-store", response.headers["Cache-Control"]
    patch admin_shop_path(@shop), headers: @headers.merge("ACCEPT" => "application/json", "X-CSRF-Token" => token), params: {
      inline_tabelog_update: "1", shop: { tabelog_url: url }
    }
    assert_response :success
    assert_equal url, @shop.reload.tabelog_url
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  test "inline not found saves without redirect and clears candidate and affiliate fields" do
    @shop.update!(tabelog_candidate_url: "https://tabelog.com/candidate/", tabelog_affiliate_url: "https://example.test/affiliate")
    assert_enqueued_with(job: AicooActivityDeliveryJob) do
      patch mark_tabelog_not_found_admin_shop_path(@shop), headers: @headers.merge("ACCEPT" => "application/json")
    end
    assert_response :success
    assert_equal "食べログなしとして登録しました", response.parsed_body["message"]
    @shop.reload
    assert_match %r{\Ahttps://not-found\.local/}, @shop.tabelog_url
    assert_equal "admin_not_found", @shop.tabelog_match_method
    assert_nil @shop.tabelog_affiliate_url
    assert_nil @shop.tabelog_candidate_url
    assert @shop.approved?
    get admin_shops_path(status: "tabelog_missing"), headers: @headers
    assert_select "a[href^='/panel_8m4k/shops/#{@shop.id}/edit']", count: 0
  end

  test "not found errors keep the record unchanged and ordinary forms still redirect" do
    @shop.update_column(:name, "")
    patch mark_tabelog_not_found_admin_shop_path(@shop), headers: @headers.merge("ACCEPT" => "application/json")
    assert_response :unprocessable_entity
    assert response.parsed_body["error"].present?
    assert_nil @shop.reload.tabelog_url
    @shop.update_column(:name, "通常フォーム")
    patch mark_tabelog_not_found_admin_shop_path(@shop), headers: @headers, params: { status: "tabelog_missing" }
    assert_redirected_to admin_shops_path(status: "tabelog_missing")
  end

  test "saved affiliates move from missing list to configured list" do
    get admin_shops_path(status: "tabelog_missing"), headers: @headers
    assert_select "form[data-inline-tabelog-form][data-shop-id='#{@shop.id}'][action*='/shops/#{@shop.id}?']", count: 1
    assert_select "a[data-tabelog-search-shop-id='#{@shop.id}'][target='_blank']", count: 1
    patch admin_shop_path(@shop), headers: @headers.merge("ACCEPT" => "application/json"), params: {
      inline_tabelog_update: "1", shop: { tabelog_url: "https://tabelog.com/test/" }
    }
    assert_response :success
    get admin_shops_path(status: "tabelog_missing"), headers: @headers
    assert_select "a[href^='/panel_8m4k/shops/#{@shop.id}/edit']", count: 0
    get admin_shops_path(status: "tabelog_configured"), headers: @headers
    assert_response :success
    assert_select "a[href^='/panel_8m4k/shops/#{@shop.id}/edit']", count: 1
    assert_select "input[name='shop[tabelog_url]'][value='https://tabelog.com/test/']", count: 1
  end

  test "inline URL update saves only URL fields without synchronous external delivery" do
    @shop.update!(opening_hours_text: "月 11:00-20:00")
    original_name = @shop.name
    original_hours = @shop.opening_hours_text
    url = "https://tabelog.com/osaka/A2701/A270406/27080719/"
      assert_enqueued_with(job: AicooActivityDeliveryJob) do
        patch admin_shop_path(@shop), headers: @headers.merge("ACCEPT" => "application/json"), params: {
          inline_tabelog_update: "1", commit_action: "reject", shop: { tabelog_url: url, name: "ignored", opening_hours_text: "ignored" }
        }
      end
    assert_response :success
    assert_equal "更新しました", response.parsed_body["message"]
    assert_equal url, response.parsed_body["url"]
    @shop.reload
    assert_equal url, @shop.tabelog_url
    assert_includes @shop.tabelog_affiliate_url, "ck.jp.ap.valuecommerce.com"
    assert_equal "admin_manual", @shop.tabelog_match_method
    assert_equal original_name, @shop.name
    assert_equal original_hours, @shop.opening_hours_text
    assert @shop.approved?
    refute @shop.rejected?
  end

  test "inline candidate update saves affiliate URL and rejects invalid input" do
    url = "https://tabelog.com/osaka/A2701/A270406/27080719/"
    patch admin_shop_path(@shop), headers: @headers.merge("ACCEPT" => "application/json"), params: {
      inline_tabelog_update: "1", shop: { tabelog_candidate_url: url }
    }
    assert_response :success
    assert_equal url, @shop.reload.tabelog_candidate_url
    assert_includes @shop.tabelog_candidate_affiliate_url, "ck.jp.ap.valuecommerce.com"
    assert_nil @shop.tabelog_url
    ["", "javascript:alert(1)", "https://bad url"].each do |bad_url|
      patch admin_shop_path(@shop), headers: @headers.merge("ACCEPT" => "application/json"), params: {
        inline_tabelog_update: "1", shop: { tabelog_candidate_url: bad_url }
      }
      assert_response :unprocessable_entity
      assert_equal "正しいURLを入力してください", response.parsed_body["error"]
      assert_equal url, @shop.reload.tabelog_candidate_url
    end
  end

  test "inline URL update supports regular form fallback and model errors" do
    patch admin_shop_path(@shop), headers: @headers, params: {
      inline_tabelog_update: "1", status: "tabelog_missing", shop: { tabelog_url: "https://tabelog.com/test/" }
    }
    assert_redirected_to admin_shops_path(status: "tabelog_missing")
    @shop.update_column(:name, "")
    patch admin_shop_path(@shop), headers: @headers.merge("ACCEPT" => "application/json"), params: {
      inline_tabelog_update: "1", shop: { tabelog_url: "https://tabelog.com/other/" }
    }
    assert_response :unprocessable_entity
    assert response.parsed_body["error"].present?
    assert_equal "https://tabelog.com/test/", @shop.reload.tabelog_url
  end

  test "situational smoking note saves displays and clears independently of time" do
    note = "お子様がいるときは禁煙。混雑時はスタッフに確認。"
    patch admin_shop_path(@shop), headers: @headers, params: { shop: {
      smoking_condition_schedules: { primary: { mode: "", situation_note: note } }
    } }
    assert_response :redirect
    assert_equal note, @shop.reload.smoking_situation_note("primary")
    get edit_admin_shop_path(@shop), headers: @headers
    assert_select 'details.smoking-advanced-settings[open]', count: 1
    assert_select '#smoking_situation_primary', text: note
    get shop_path(@shop)
    assert_response :success
    assert_includes response.body, note
    assert_includes response.body, "状況による喫煙条件"
    assert_includes response.body, "状況により禁煙・要確認"
    patch admin_shop_path(@shop), headers: @headers, params: { shop: {
      smoking_condition_schedules: { primary: { mode: "", situation_note: "" } }
    } }
    assert_equal({}, @shop.reload.smoking_condition_schedules)
    get edit_admin_shop_path(@shop), headers: @headers
    assert_select 'details.smoking-advanced-settings:not([open])', count: 1
  end

  test "lunch-time ban with no lunch hours previews unset smoking time" do
    get new_admin_shop_import_path, headers: @headers, params: { raw_text: "店名\nヤマダ カフェ\n営業時間\n11:30 - 21:00\n禁煙・喫煙\n分煙\nランチ時間は禁煙\n駐車場\n有" }
    assert_response :success
    assert_select 'tr', text: /喫煙エリア\s*all_smoking/
    assert_select 'tr', text: /喫煙タイプ\s*both_ok/
    assert_select 'tr', text: /喫煙可能時間帯\s*未設定/
  end

  test "seat location saves independently of time and keeps details open" do
    patch admin_shop_path(@shop), headers: @headers, params: { shop: {
      smoking_condition_schedules: { primary: { mode: "", hours_text: "", seat_location: "terrace" } }
    } }
    assert_response :redirect
    assert_equal "terrace", @shop.reload.smoking_condition_schedules.dig("primary", "seat_location")
    refute @shop.advanced_smoking_schedules?
    get edit_admin_shop_path(@shop), headers: @headers
    assert_select 'details.smoking-advanced-settings[open]', count: 1
    assert_select '#smoking_seat_location_primary option[selected]', text: "テラス席"
    get shop_path(@shop)
    assert_response :success
    assert_includes response.body, "喫煙できる席"
    assert_includes response.body, "テラス席"
    patch admin_shop_path(@shop), headers: @headers, params: { shop: {
      smoking_condition_schedules: { primary: { mode: "", seat_location: "" } }
    } }
    assert_equal({}, @shop.reload.smoking_condition_schedules)
  end

  test "unknown night smoking is labeled explicitly in import preview" do
    get new_admin_shop_import_path, headers: @headers, params: { raw_text: "店名\n福城\n営業時間\n11:00 - 22:00\n禁煙・喫煙\n全席喫煙可\n夜は喫煙可\n駐車場\n無" }
    assert_response :success
    assert_select 'tr', text: /喫煙可能時間帯\s*未設定/
    assert_select 'tr', text: /条件別の詳細時間\s*未取得/
  end

  test "timed tobacco import saves advanced settings and blank-only merge cannot change existing permissions" do
    raw = "店名\n時間別インポート\n住所\n大阪府大阪市北区梅田1-20\nジャンル\n居酒屋\n営業時間\n16:00 - 04:00\n禁煙・喫煙\n全席喫煙可\n※加熱式タバコ限定（22時以降、紙タバコも喫煙可）\n駐車場\n無"
    assert_difference("Shop.count", 1) do
      post admin_shop_import_path, headers: @headers, params: { raw_text: raw, force_new: "1" }
    end
    assert_response :redirect
    imported = Shop.find_by!(name: "時間別インポート")
    assert_equal "electronic_only", imported.smoking_type
    assert_equal "both_ok", imported.smoking_type_2
    assert_equal "22:00-04:00", imported.smoking_condition_schedules.dig("secondary", "hours_text")
    get edit_admin_shop_path(imported, from: "shop_import"), headers: @headers
    assert_select 'details.smoking-advanced-settings[open]', count: 1
    assert_select '#smoking_schedule_primary_mode option[selected]', text: "営業時間と同じ"
    assert_select '#smoking_schedule_secondary_hours', text: "22:00-04:00"
    post admin_shop_import_path, headers: @headers, params: { raw_text: raw, target_shop_id: @shop.id }
    assert_response :redirect
    assert_equal "both_ok", @shop.reload.smoking_type
    assert_equal({}, @shop.smoking_condition_schedules)
  end

  test "configured advanced schedules open automatically and survive save and reload" do
    get edit_admin_shop_path(@shop), headers: @headers
    assert_response :success
    assert_select 'details.smoking-advanced-settings:not([open])', count: 1
    assert_select 'details.smoking-advanced-settings #shop_smoking_area_2', count: 1
    assert_select '#smoking_schedule_primary_mode', count: 1
    schedules = { primary: { mode: "business" }, secondary: { mode: "custom", hours_text: "22:00-04:00" } }
    patch admin_shop_path(@shop), headers: @headers, params: { shop: {
      smoking_type: "electronic_only", smoking_area_2: "all_smoking", smoking_type_2: "paper_only", smoking_condition_schedules: schedules
    } }
    assert_response :redirect
    assert_equal "22:00-04:00", @shop.reload.smoking_condition_schedules.dig("secondary", "hours_text")
    get edit_admin_shop_path(@shop), headers: @headers
    assert_select '#smoking_schedule_secondary_hours', text: "22:00-04:00"
    assert_select 'details.smoking-advanced-settings[open]', count: 1
    patch admin_shop_path(@shop), headers: @headers, params: { shop: { name: @shop.name } }
    assert_equal "business", @shop.reload.smoking_condition_schedules.dig("primary", "mode")
    get shop_path(@shop)
    assert_response :success
    assert_includes response.body, "22:00-04:00"
    patch admin_shop_path(@shop), headers: @headers, params: { shop: { smoking_condition_schedules: { primary: { mode: "" }, secondary: { mode: "" } } } }
    assert_response :redirect
    assert_equal({}, @shop.reload.smoking_condition_schedules)
  end

  test "multiple detailed windows survive saving and reopening the form" do
    schedule = "月 07:00-11:00, 12:30-21:00\n火 07:00-11:00, 12:30-21:00\n日 喫煙不可"
    patch admin_shop_path(@shop), headers: @headers, params: { shop: {
      smoking_condition_schedules: { primary: { mode: "custom", hours_text: schedule } }
    } }
    assert_response :redirect
    assert_equal schedule, @shop.reload.smoking_condition_schedules.dig("primary", "hours_text")
    get edit_admin_shop_path(@shop), headers: @headers
    assert_select 'details.smoking-advanced-settings[open]', count: 1
    assert_select '#smoking_schedule_primary_hours', text: schedule
    assert_select '[data-action="smoking-windows#add"]', count: 2
  end

  test "business-only timing without additional details stays collapsed" do
    @shop.update!(smoking_condition_schedules: { primary: { mode: "business" } })
    get edit_admin_shop_path(@shop), headers: @headers
    assert_response :success
    assert_select 'details.smoking-advanced-settings:not([open])', count: 1
    refute_includes response.body, "［詳細設定あり］"
  end

  test "a partially entered secondary condition opens detailed settings" do
    @shop.update!(smoking_area_2: "all_smoking")
    get edit_admin_shop_path(@shop), headers: @headers
    assert_response :success
    assert_select 'details.smoking-advanced-settings[open]', count: 1
    assert_includes response.body, "［詳細設定あり］"
  end

  test "imported weekday nonsmoking checkbox survives saving without closing business" do
    result = TabelogPasteParser.call("店名\n曜日テスト\n営業時間\n17:00 - 23:00\n禁煙・喫煙\n全席喫煙可\n日曜日のみ全席禁煙\n駐車場\n無")
    @shop.update!(opening_hours_text: result[:opening_hours_text], smoking_hours_text: result[:smoking_hours_text])
    get edit_admin_shop_path(@shop), headers: @headers
    assert_response :success
    assert_select '[data-hours-row="sun"] [data-smoking-nonsmoking][checked]', count: 1
    assert_select '[data-hours-row="mon"] [data-smoking-nonsmoking][checked]', count: 0
    schedule = "月 時間未設定\n火 喫煙不可\n日 喫煙不可"
    patch admin_shop_path(@shop), params: { shop: { smoking_hours_text: schedule } }, headers: @headers
    assert_response :redirect
    assert_equal schedule, @shop.reload.smoking_hours_text
    get edit_admin_shop_path(@shop), headers: @headers
    assert_select '[data-hours-row="tue"] [data-smoking-nonsmoking][checked]', count: 1
    assert_select '[data-hours-row="mon"]' do
      assert_select '[data-smoking-nonsmoking][checked]', count: 0
      assert_select '[data-smoking-same][checked]', count: 0
      assert_select '[data-smoking-start] option[selected]', text: "未設定"
    end
  end

  test "admin editing shows and preserves both smoking periods around lunch" do
    @shop.update!(opening_hours_text: "月 10:30-20:45", smoking_hours_text: "月 10:30 - 11:30, 14:00 - 20:45")
    get edit_admin_shop_path(@shop), headers: @headers
    assert_response :success
    assert_select '[data-hours-row="mon"][data-extra-smoking-ranges="14:00-20:45"]' do
      assert_select '[data-smoking-start] option[selected]', text: "10:30"
      assert_select '[data-smoking-end] option[selected]', text: "11:30"
    end
    assert_includes response.body, "喫煙可2：14:00-20:45"
    patch admin_shop_path(@shop), params: { shop: { name: @shop.name } }, headers: @headers
    assert_response :redirect
    assert_equal "月 10:30 - 11:30, 14:00 - 20:45", @shop.reload.smoking_hours_text
  end

  test "ambiguous lunch restriction is explicitly marked for confirmation in import preview" do
    get new_admin_shop_import_path, params: { raw_text: "店名\n時刻不明テスト\n営業時間\n07:00 - 09:30\n11:30 - 13:30\n17:30 - 21:30\n禁煙・喫煙\n分煙\nランチタイムは禁煙タイムあります\n駐車場\n有" }, headers: @headers
    assert_response :success
    assert_includes response.body, "未設定（禁煙時間不明・要確認）"
  end

  test "unknown lunch restriction stays unset in admin editing and after saving" do
    @shop.update!(public_store_details: "分煙\nランチタイム禁煙", smoking_hours_text: nil,
      opening_hours_text: "月 11:00-21:00", opening_hours_json: { monday: { open: "11:00", close: "21:00" } })
    get edit_admin_shop_path(@shop), headers: @headers
    assert_response :success
    assert_select '[data-hours-row="mon"][data-smoking-hours-unknown="true"]' do
      assert_select '[data-smoking-same][checked]', count: 0
      assert_select '[data-smoking-start] option[selected]', text: "未設定"
      assert_select '[data-smoking-end] option[selected]', text: "未設定"
    end
    patch admin_shop_path(@shop), params: { shop: { name: @shop.name } }, headers: @headers
    assert_response :redirect
    assert @shop.reload.smoking_hours_unset_with_restriction?
    assert_nil @shop.smoking_hours_text
    assert_includes @shop.public_store_details, "ランチタイム禁煙"
  end

  test "admin tracking defaults to excluded but explicit inclusion persists" do
    get "/panel_8m4k/analytics", headers: @headers
    assert_response :success
    assert_includes response.body, "現在、この端末のフロント閲覧はアクセス集計から除外されています。"
    assert_no_difference("PageView.count") { get "/", headers: @headers }

    delete admin_include_page_view_tracking_path, headers: @headers
    get "/panel_8m4k/analytics", headers: @headers
    assert_includes response.body, "現在、この端末のフロント閲覧はアクセス集計の対象です。"
    post admin_exclude_page_view_tracking_path, headers: @headers
    get "/panel_8m4k/analytics", headers: @headers
    assert_includes response.body, "現在、この端末のフロント閲覧はアクセス集計から除外されています。"
  end

  test "import and edit screens hide device tracking controls" do
    [admin_shops_path, new_admin_shop_import_path, edit_admin_shop_path(@shop)].each do |path|
      get path, headers: @headers
      assert_response :success
      refute_includes response.body, "この端末のアクセス集計"
      assert_select "form[action='#{admin_include_page_view_tracking_path}']", count: 0
    end
  end

  test "admin lists forms detail analytics and approval queues render without public styling" do
    paths = %w[/panel_8m4k/shops /panel_8m4k/shops/new /panel_8m4k/shops/holds /panel_8m4k/shops/smoking_unverified /panel_8m4k/shops/phone_check_holds /panel_8m4k/shops/clicks /panel_8m4k/reviews /panel_8m4k/shop_edit_requests /panel_8m4k/shop_reports /panel_8m4k/contact_messages /panel_8m4k/articles /panel_8m4k/articles/new /panel_8m4k/affiliate_ads /panel_8m4k/affiliate_ads/new /panel_8m4k/sub_admin_users /panel_8m4k/sub_admin_users/new /panel_8m4k/shop_verification_submissions /panel_8m4k/analytics]
    paths += [ "/panel_8m4k/shops/#{@shop.id}", "/panel_8m4k/shops/#{@shop.id}/edit", "/panel_8m4k/shop_edit_requests/#{@edit.id}", "/panel_8m4k/shop_reports/#{@report.id}", "/panel_8m4k/contact_messages/#{@contact.id}", "/panel_8m4k/articles/#{@article.slug}/edit", "/panel_8m4k/affiliate_ads/#{@ad.id}/edit", "/panel_8m4k/sub_admin_users/#{@user.id}/edit" ]
    failures = []
    paths.each do |path|
      get path, headers: @headers
      failures << [ path, response.status ] unless response.status == 200
      if response.status == 200
        assert_select "body.admin-layout", count: 1
        assert_select "body.suelog-refine", count: 0
        assert_select 'link[href*="refine"]', count: 0
      end
    end
    assert_empty failures
  end

  test "shop approval rejection hold and edit preserve database and public visibility" do
    @shop.update!(approved: false)
    patch "/panel_8m4k/shops/#{@shop.id}/approve", headers: @headers
    assert_response :redirect; assert @shop.reload.approved?
    get "/", headers: @headers; assert_select ".shop-card__titleLink", text: @shop.name
    patch "/panel_8m4k/shops/#{@shop.id}", params: { shop: { name: "\u7BA1\u7406\u7DE8\u96C6\u6E08\u307F" } }, headers: @headers
    assert_response :redirect; assert_equal "\u7BA1\u7406\u7DE8\u96C6\u6E08\u307F", @shop.reload.name
    patch "/panel_8m4k/shops/#{@shop.id}/hold", headers: @headers
    assert @shop.reload.on_hold?; assert_not @shop.approved?
    patch "/panel_8m4k/shops/#{@shop.id}/reject", headers: @headers
    assert @shop.reload.rejected?; assert_not @shop.approved?
    get "/", headers: @headers; assert_select ".shop-card__titleLink", text: "\u7BA1\u7406\u7DE8\u96C6\u6E08\u307F", count: 0
  end

  test "review approval becomes public and rejection removes the local review" do
    patch "/panel_8m4k/reviews/#{@review.id}/approve", headers: @headers
    assert_response :redirect; assert @review.reload.approved?
    get shop_path(@shop); assert_includes response.body, "\u627F\u8A8D\u691C\u8A3C"
    assert_difference("Review.count", -1) { patch "/panel_8m4k/reviews/#{@review.id}/reject", headers: @headers }
    assert_response :redirect
  end

  test "edit approvals apply smoking information and rejection does not change the shop" do
    patch "/panel_8m4k/shop_edit_requests/#{@edit.id}/approve", headers: @headers
    assert_response :redirect; assert @edit.reload.approved?
    assert_equal "\u7BA1\u7406\u4FEE\u6B63\u5E97\u8217", @shop.reload.name
    assert_equal "separated", @shop.smoking_area
    assert_equal "electronic_only", @shop.smoking_type
    rejected = @shop.shop_edit_requests.create!(proposed_name: "\u5374\u4E0B\u3055\u308C\u308B\u540D\u524D", proposed_smoking_area: "area_all_smoking", proposed_smoking_type: "type_paper_only")
    patch "/panel_8m4k/shop_edit_requests/#{rejected.id}/reject", headers: @headers
    assert rejected.reload.rejected?; assert_equal "\u7BA1\u7406\u4FEE\u6B63\u5E97\u8217", @shop.reload.name
  end

  test "report resolution holds the shop and report rejection preserves its state" do
    patch "/panel_8m4k/shop_reports/#{@report.id}/resolve", headers: @headers
    assert_response :redirect; assert @report.reload.resolved?
    assert @shop.reload.on_hold?; assert_not @shop.approved?
    second = @shop.shop_reports.create!(reason: "\u305D\u306E\u4ED6")
    patch "/panel_8m4k/shop_reports/#{second.id}/reject", headers: @headers
    assert second.reload.rejected?; assert @shop.reload.on_hold?
  end

  test "article creation editing publication and local ad activation persist correctly" do
    post "/panel_8m4k/articles", params: { article: { title: "\u7BA1\u7406\u767B\u9332\u8A18\u4E8B", slug: "admin-created", body: "<h2>\u7BA1\u7406\u30C6\u30B9\u30C8</h2>", published: false } }, headers: @headers
    assert_response :redirect
    article = Article.find_by!(slug: "admin-created")
    patch "/panel_8m4k/articles/#{article.slug}", params: { article: { title: "\u7BA1\u7406\u7DE8\u96C6\u8A18\u4E8B", published: true, published_at: 1.hour.ago } }, headers: @headers
    assert_response :redirect; assert_equal "\u7BA1\u7406\u7DE8\u96C6\u8A18\u4E8B", article.reload.title
    get article_path(article); assert_response :success
    post "/panel_8m4k/affiliate_ads", params: { affiliate_ad: { key: "admin-created", url: "/privacy", image_path: "refine/shop-bar.jpg", active: true } }, headers: @headers
    assert_response :redirect
    ad = AffiliateAd.find_by!(key: "admin-created")
    patch "/panel_8m4k/affiliate_ads/#{ad.id}", params: { affiliate_ad: { active: false, url: "/terms" } }, headers: @headers
    assert_response :redirect; assert_not ad.reload.active?; assert_equal "/terms", ad.url
  end

  test "sub admin authentication submissions editing moderation and logout work" do
    get "/sub_admin"; assert_redirected_to "/sub_admin/login"
    post "/sub_admin/login", params: { login_id: @user.login_id, password: "wrong" };assert_response :unprocessable_entity
    post "/sub_admin/login", params: { login_id: @user.login_id, password: "local-test-only-12345" };assert_redirected_to "/sub_admin"
    follow_redirect!;assert_response :success
    assert_difference("ShopVerificationSubmission.count", 1) do
      post "/sub_admin/smoking_checks", params: { shop_id: @shop.id, smoking_location: "seat_smoking", tobacco_type: "both", memo: "\u78BA\u8A8D\u6E08\u307F" }
    end
    submission=@user.shop_verification_submissions.last
    get "/sub_admin/smoking_checks/#{submission.id}/edit";assert_response :success
    patch "/sub_admin/smoking_checks/#{submission.id}", params: { smoking_location: "smoking_area_only", tobacco_type: "heated_only", memo: "\u30ED\u30FC\u30AB\u30EB\u4FEE\u6B63" }
    assert_equal "heated_only", submission.reload.tobacco_type
    patch "/panel_8m4k/shop_verification_submissions/#{submission.id}/approve", headers: @headers
    assert_response :redirect;assert_equal "approved", submission.reload.status
    assert_equal "separated", @shop.reload.smoking_area
    assert_equal "electronic_only", @shop.smoking_type
    get "/sub_admin/smoking_checks/#{submission.id}/edit";assert_response :redirect
    delete "/sub_admin/logout"; assert_redirected_to "/sub_admin/login"
    get "/sub_admin"; assert_redirected_to "/sub_admin/login"
  end
end
