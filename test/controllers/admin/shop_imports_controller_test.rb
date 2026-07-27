require "test_helper"

class Admin::ShopImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @auth_headers = {
      "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(
        "kawa_admin_92",
        "X9f!pL3#sK"
      )
    }
  end

  test "preview keeps the Enter registration flow and submit guard" do
    post preview_admin_shop_import_path,
         params: { raw_text: tabelog_text("確認フローテスト店舗") },
         headers: @auth_headers

    assert_response :success
    assert_select '[data-controller="single-submit"]', count: 1
    assert_select 'input[type="submit"][value="この内容で新規仮登録する"]', count: 1
  end

  test "create saves one provisional shop and queues activity delivery" do
    deliveries = []

    with_replaced_method(AicooActivityDeliveryJob, :perform_later, ->(attributes) { deliveries << attributes }) do
      assert_difference("Shop.count", 1) do
        post admin_shop_import_path,
             params: { raw_text: tabelog_text("仮登録テスト店舗"), force_new: "1" },
             headers: @auth_headers
      end
    end

    shop = Shop.order(:id).last
    assert_redirected_to edit_admin_shop_path(shop, from: "shop_import")
    assert_equal "tabelog_paste", shop.import_source
    assert_equal false, shop.approved?
    assert_equal 1, deliveries.size
    assert_equal "data_added", deliveries.first[:activity_type]
    assert_equal shop.id, deliveries.first[:source_id]
  end

  test "final approval uses the provisional shop and queues activity delivery" do
    shop = Shop.create!(
      name: "本登録テスト店舗",
      address: "大阪府大阪市北区梅田9-9-9",
      area: "梅田",
      genre: "居酒屋",
      last_confirmed_on: Date.current,
      import_source: "tabelog_paste"
    )
    deliveries = []

    with_replaced_method(AicooActivityDeliveryJob, :perform_later, ->(attributes) { deliveries << attributes }) do
      patch admin_shop_path(shop),
            params: {
              from: "shop_import",
              commit_action: "approve",
              shop: {
                name: shop.name,
                address: shop.address,
                area: shop.area,
                genre: shop.genre,
                last_confirmed_on: shop.last_confirmed_on
              }
            },
            headers: @auth_headers
    end

    assert_redirected_to new_admin_shop_import_path
    assert shop.reload.approved?
    assert_equal 1, deliveries.size
    assert_equal "data_updated", deliveries.first[:activity_type]
  end

  test "import edit form keeps the Enter approval flow and submit guard" do
    shop = Shop.create!(
      name: "本登録画面テスト店舗",
      address: "大阪府大阪市北区梅田6-6-6",
      area: "梅田",
      genre: "居酒屋",
      last_confirmed_on: Date.current,
      import_source: "tabelog_paste"
    )

    get edit_admin_shop_path(shop, from: "shop_import"), headers: @auth_headers

    assert_response :success
    assert_select 'form[data-controller="single-submit"]', count: 1
    assert_select 'input[type="submit"][name="commit_action"][value="approve"]', count: 1
  end

  test "activity enqueue failure does not fail provisional registration" do
    replacement = lambda do |_attributes|
      raise ActiveJob::EnqueueError, "queue unavailable"
    end

    with_replaced_method(AicooActivityDeliveryJob, :perform_later, replacement) do
      assert_difference("Shop.count", 1) do
        post admin_shop_import_path,
             params: { raw_text: tabelog_text("通知失敗テスト店舗"), force_new: "1" },
             headers: @auth_headers
      end
    end

    shop = Shop.order(:id).last
    assert_redirected_to edit_admin_shop_path(shop, from: "shop_import")
    assert_equal "tabelog_paste", shop.import_source
  end

  test "duplicate warning and validation behavior stay unchanged" do
    existing = Shop.create!(
      name: "重複確認テスト店舗",
      address: "大阪府大阪市中央区難波8-8-8",
      area: "難波",
      genre: "居酒屋",
      last_confirmed_on: Date.current,
      approved: true,
      rejected: false,
      on_hold: false
    )

    post preview_admin_shop_import_path,
         params: { raw_text: tabelog_text(existing.name, address: existing.address) },
         headers: @auth_headers

    assert_response :success
    assert_select "h3", text: "重複候補があります"
    assert_select "a[href='#{edit_admin_shop_path(existing)}']"

    assert_no_difference("Shop.count") do
      post admin_shop_import_path,
           params: { raw_text: "" },
           headers: @auth_headers
    end
    assert_redirected_to new_admin_shop_import_path
  end

  private

  def tabelog_text(name, address: "大阪府大阪市北区梅田1-2-3")
    <<~TEXT
      店名
      #{name}
      ジャンル
      居酒屋
      住所
      #{address}
      交通手段
      大阪駅から200m
      禁煙・喫煙
      全席喫煙可
    TEXT
  end

  def with_replaced_method(object, method_name, replacement)
    original = object.method(method_name)
    object.define_singleton_method(method_name, replacement)
    yield
  ensure
    object.define_singleton_method(method_name, original)
  end
end
