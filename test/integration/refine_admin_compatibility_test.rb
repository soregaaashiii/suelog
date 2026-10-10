require 'test_helper'

class RefineAdminCompatibilityTest < ActionDispatch::IntegrationTest
  setup do
    # Authenticate only against the isolated application's existing configuration.
    # Do not embed credentials in the migration package or test output.
    config = Rails.root.join('app/controllers/admin/base_controller.rb').read
    credentials = config.match(/name: "([^"]+)", password: "([^"]+)"/)
    raise 'Admin authentication configuration changed' unless credentials
    @headers = { 'HTTP_AUTHORIZATION' => ActionController::HttpAuthentication::Basic.encode_credentials(credentials[1], credentials[2]) }
    Geocoder.configure(lookup: :test)
    Geocoder::Lookup::Test.set_default_stub([])
    @shop = Shop.create!(name: '管理検証店舗', address: '大阪市北区梅田1-20', genre: '居酒屋', last_confirmed_on: Date.current, smoking_area: :all_smoking, smoking_type: :both_ok, smoking_unverified: true, approved: true)
    @review = @shop.reviews.create!(rating: 4, ip_hash: 'admin-compatibility', comment: '承認検証', approved: false)
    @edit = @shop.shop_edit_requests.create!(proposed_name: '管理修正店舗', proposed_smoking_area: 'area_separated', proposed_smoking_type: 'type_electronic_only')
    @report = @shop.shop_reports.create!(reason: '禁煙になった', detail: 'ローカル検証', status: :pending)
    @contact = ContactMessage.create!(name: '確認者', email: 'local@example.test', subject: '管理画面検証', body: 'ローカル専用')
    @article = Article.create!(title: '管理検証記事', slug: 'admin-compatibility', published: false)
    @ad = AffiliateAd.create!(key: 'admin-compatibility', url: '/terms', image_path: 'refine/shop-bar.jpg', active: true)
    @user = SubAdminUser.create!(name: 'ローカル確認者', login_id: 'refine-local-admin', password: 'local-test-only-12345', active: true, permissions: ['smoking_check'])
  end

  test 'admin lists forms detail analytics and approval queues render without public styling' do
    paths = %w[/panel_8m4k/shops /panel_8m4k/shops/new /panel_8m4k/shops/holds /panel_8m4k/shops/smoking_unverified /panel_8m4k/shops/phone_check_holds /panel_8m4k/shops/clicks /panel_8m4k/reviews /panel_8m4k/shop_edit_requests /panel_8m4k/shop_reports /panel_8m4k/contact_messages /panel_8m4k/articles /panel_8m4k/articles/new /panel_8m4k/affiliate_ads /panel_8m4k/affiliate_ads/new /panel_8m4k/sub_admin_users /panel_8m4k/sub_admin_users/new /panel_8m4k/shop_verification_submissions /panel_8m4k/analytics]
    paths += ["/panel_8m4k/shops/#{@shop.id}", "/panel_8m4k/shops/#{@shop.id}/edit", "/panel_8m4k/shop_edit_requests/#{@edit.id}", "/panel_8m4k/shop_reports/#{@report.id}", "/panel_8m4k/contact_messages/#{@contact.id}", "/panel_8m4k/articles/#{@article.slug}/edit", "/panel_8m4k/affiliate_ads/#{@ad.id}/edit", "/panel_8m4k/sub_admin_users/#{@user.id}/edit"]
    failures = []
    paths.each do |path|
      get path, headers: @headers
      failures << [path, response.status] unless response.status == 200
      if response.status == 200
        assert_select 'body.admin-layout', count: 1
        assert_select 'body.suelog-refine', count: 0
        assert_select 'link[href*="refine"]', count: 0
      end
    end
    assert_empty failures
  end

  test 'shop approval rejection hold and edit preserve database and public visibility' do
    @shop.update!(approved: false)
    patch "/panel_8m4k/shops/#{@shop.id}/approve", headers: @headers
    assert_response :redirect; assert @shop.reload.approved?
    get '/', headers: @headers; assert_select '.shop-card__titleLink', text: @shop.name
    patch "/panel_8m4k/shops/#{@shop.id}", params: {shop: {name:'管理編集済み'}}, headers: @headers
    assert_response :redirect; assert_equal '管理編集済み', @shop.reload.name
    patch "/panel_8m4k/shops/#{@shop.id}/hold", headers: @headers
    assert @shop.reload.on_hold?; assert_not @shop.approved?
    patch "/panel_8m4k/shops/#{@shop.id}/reject", headers: @headers
    assert @shop.reload.rejected?; assert_not @shop.approved?
    get '/', headers: @headers; assert_select '.shop-card__titleLink', text: '管理編集済み', count: 0
  end

  test 'review approval becomes public and rejection removes the local review' do
    patch "/panel_8m4k/reviews/#{@review.id}/approve", headers: @headers
    assert_response :redirect; assert @review.reload.approved?
    get shop_path(@shop); assert_includes response.body, '承認検証'
    assert_difference('Review.count', -1) { patch "/panel_8m4k/reviews/#{@review.id}/reject", headers: @headers }
    assert_response :redirect
  end

  test 'edit approvals apply smoking information and rejection does not change the shop' do
    patch "/panel_8m4k/shop_edit_requests/#{@edit.id}/approve", headers: @headers
    assert_response :redirect; assert @edit.reload.approved?
    assert_equal '管理修正店舗', @shop.reload.name
    assert_equal 'separated', @shop.smoking_area
    assert_equal 'electronic_only', @shop.smoking_type
    rejected = @shop.shop_edit_requests.create!(proposed_name: '却下される名前', proposed_smoking_area: 'area_all_smoking', proposed_smoking_type: 'type_paper_only')
    patch "/panel_8m4k/shop_edit_requests/#{rejected.id}/reject", headers: @headers
    assert rejected.reload.rejected?; assert_equal '管理修正店舗', @shop.reload.name
  end

  test 'report resolution holds the shop and report rejection preserves its state' do
    patch "/panel_8m4k/shop_reports/#{@report.id}/resolve", headers: @headers
    assert_response :redirect; assert @report.reload.resolved?
    assert @shop.reload.on_hold?; assert_not @shop.approved?
    second = @shop.shop_reports.create!(reason: 'その他')
    patch "/panel_8m4k/shop_reports/#{second.id}/reject", headers: @headers
    assert second.reload.rejected?; assert @shop.reload.on_hold?
  end

  test 'article creation editing publication and local ad activation persist correctly' do
    post '/panel_8m4k/articles', params: {article:{title:'管理登録記事',slug:'admin-created',body:'<h2>管理テスト</h2>',published:false}}, headers: @headers
    assert_response :redirect
    article = Article.find_by!(slug:'admin-created')
    patch "/panel_8m4k/articles/#{article.slug}", params:{article:{title:'管理編集記事',published:true,published_at:1.hour.ago}}, headers:@headers
    assert_response :redirect; assert_equal '管理編集記事', article.reload.title
    get article_path(article); assert_response :success
    post '/panel_8m4k/affiliate_ads', params:{affiliate_ad:{key:'admin-created',url:'/privacy',image_path:'refine/shop-bar.jpg',active:true}},headers:@headers
    assert_response :redirect
    ad = AffiliateAd.find_by!(key:'admin-created')
    patch "/panel_8m4k/affiliate_ads/#{ad.id}",params:{affiliate_ad:{active:false,url:'/terms'}},headers:@headers
    assert_response :redirect; assert_not ad.reload.active?; assert_equal '/terms', ad.url
  end

  test 'sub admin authentication submissions editing moderation and logout work' do
    get '/sub_admin'; assert_redirected_to '/sub_admin/login'
    post '/sub_admin/login',params:{login_id:@user.login_id,password:'wrong'};assert_response :unprocessable_entity
    post '/sub_admin/login',params:{login_id:@user.login_id,password:'local-test-only-12345'};assert_redirected_to '/sub_admin'
    follow_redirect!;assert_response :success
    assert_difference('ShopVerificationSubmission.count',1) do
      post '/sub_admin/smoking_checks',params:{shop_id:@shop.id,smoking_location:'seat_smoking',tobacco_type:'both',memo:'確認済み'}
    end
    submission=@user.shop_verification_submissions.last
    get "/sub_admin/smoking_checks/#{submission.id}/edit";assert_response :success
    patch "/sub_admin/smoking_checks/#{submission.id}",params:{smoking_location:'smoking_area_only',tobacco_type:'heated_only',memo:'ローカル修正'}
    assert_equal 'heated_only',submission.reload.tobacco_type
    patch "/panel_8m4k/shop_verification_submissions/#{submission.id}/approve",headers:@headers
    assert_response :redirect;assert_equal 'approved',submission.reload.status
    assert_equal 'separated',@shop.reload.smoking_area
    assert_equal 'electronic_only',@shop.smoking_type
    get "/sub_admin/smoking_checks/#{submission.id}/edit";assert_response :redirect
    delete '/sub_admin/logout'; assert_redirected_to '/sub_admin/login'
    get '/sub_admin'; assert_redirected_to '/sub_admin/login'
  end
end
