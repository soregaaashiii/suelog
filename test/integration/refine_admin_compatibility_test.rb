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

  test "unknown night smoking is labeled explicitly in import preview" do
    get new_admin_shop_import_path, headers: @headers, params: { raw_text: "店名\n福城\n営業時間\n11:00 - 22:00\n禁煙・喫煙\n全席喫煙可\n夜は喫煙可\n駐車場\n無" }
    assert_response :success
    assert_select 'tr', text: /喫煙可能時間帯\s*時間不明・要確認/
    assert_select 'tr', text: /条件別の詳細時間\s*条件1：時間不明・要確認/
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
    get admin_shops_path, headers: @headers
    assert_response :success
    assert_includes response.body, "現在、この端末のフロント閲覧はアクセス集計から除外されています。"
    assert_no_difference("PageView.count") { get "/", headers: @headers }

    delete admin_include_page_view_tracking_path, headers: @headers
    get admin_shops_path, headers: @headers
    assert_includes response.body, "現在、この端末のフロント閲覧はアクセス集計の対象です。"
    post admin_exclude_page_view_tracking_path, headers: @headers
    get admin_shops_path, headers: @headers
    assert_includes response.body, "現在、この端末のフロント閲覧はアクセス集計から除外されています。"
  end

  test "import and edit screens hide device tracking controls" do
    [new_admin_shop_import_path, edit_admin_shop_path(@shop)].each do |path|
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
