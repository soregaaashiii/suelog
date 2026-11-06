require "test_helper"
require "minitest/mock"

class HotpepperApiBatchesTest < ActionDispatch::IntegrationTest
  setup do
    credentials = Rails.root.join("app/controllers/admin/base_controller.rb").read.match(/name: "([^"]+)", password: "([^"]+)"/)
    @headers = { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(credentials[1], credentials[2]) }
    Geocoder.configure(lookup: :test)
    Geocoder::Lookup::Test.set_default_stub([])
    @old_key = ENV["HOTPEPPER_API_KEY"]
    ENV["HOTPEPPER_API_KEY"] = "test-only"
    @shop = Shop.create!(name: "APIカフェ 北店", address: "大阪府大阪市北区梅田1-2-3 第1ビル2F", genre: "居酒屋", approved: true, last_confirmed_on: Date.current)
  end
  teardown { ENV["HOTPEPPER_API_KEY"] = @old_key }

  def records
    [{ "id" => "J003451218", "name" => @shop.name, "address" => @shop.address, "urls" => { "pc" => "https://www.hotpepper.jp/strJ003451218/" } }]
  end

  def collect(entries = records)
    post admin_hotpepper_api_batches_path, headers: @headers, params: { area_filter: "大阪市北区", trial_mode: "1" }
    assert_response :see_other
    batch = HotpepperApiBatch.order(:id).last
    execution = batch.executions.sole
    factory = ->(_shop) { Struct.new(:records_for_matching).new(entries) }
    HotpepperApi::Importer.new(batch, execution, execution.run_token, client_factory: factory).call
    assert_equal "ready", batch.reload.state
    batch
  end

  def register(batch)
    target = batch.targets.find_by!(shop_id: @shop.id)
    post review_target_admin_hotpepper_api_batch_path(batch, target_id: target.id, format: :json), headers: @headers, params: { match_id: target.matches.first.id, decision: "register" }
    assert_response :success
    assert JSON.parse(response.body)["success"]
    target.reload
  end

  test "entry has search start and results reuse Enter registration UI" do
    batch = collect
    assert_nil @shop.reload.hotpepper_url
    assert_nil @shop.gurunavi_url
    get admin_hotpepper_api_batches_path, headers: @headers
    assert_response :success
    assert_select "form[action='#{admin_hotpepper_api_batches_path}']"
    assert_select "a[href='#{admin_hotpepper_api_batch_path(batch)}']", text: "照合・登録を続ける"
    get admin_hotpepper_api_batch_path(batch), headers: @headers
    assert_response :success
    assert_select "[data-controller='csv-registration']"
    assert_select "button[data-action='click->csv-registration#registerFirst']"
    assert_select "[data-csv-confidence-summary]"
    assert_select "section[data-target-shop='#{@shop.id}']"
    assert_includes response.body, "Powered by"
  end

  test "register removes from work list and undo returns it without changing other providers" do
    batch = collect
    target = register(batch)
    assert_equal "applied", target.state
    assert_equal "https://www.hotpepper.jp/strJ003451218/", @shop.reload.hotpepper_url
    assert_includes @shop.hotpepper_affiliate_url, "valuecommerce.com"
    assert_nil @shop.gurunavi_url
    get admin_hotpepper_api_batch_path(batch), headers: @headers
    assert_select "section[data-target-shop='#{@shop.id}']", count: 0
    get admin_hotpepper_api_batch_path(batch, classification: "registered"), headers: @headers
    assert_select "section[data-target-shop='#{@shop.id}']", count: 1
    post review_target_admin_hotpepper_api_batch_path(batch, target_id: target.id, format: :json), headers: @headers, params: { match_id: target.matches.first.id, decision: "undo" }
    assert_response :success
    assert_nil @shop.reload.hotpepper_url
    assert_equal "rolled_back", target.reload.state
  end

  test "exclude all candidates moves store to excluded and restore returns it" do
    batch = collect
    target = batch.targets.find_by!(shop_id: @shop.id)
    post review_target_admin_hotpepper_api_batch_path(batch, target_id: target.id, format: :json), headers: @headers, params: { decision: "exclude" }
    assert_response :success
    assert_equal "excluded", target.reload.state
    assert target.matches.all? { |match| match.state == "excluded" }
    assert_not HotpepperApiTarget.unregistered.exists?(target.id)
    post review_target_admin_hotpepper_api_batch_path(batch, target_id: target.id, format: :json), headers: @headers, params: { decision: "restore" }
    assert_response :success
    assert HotpepperApiTarget.unregistered.exists?(target.id)
  end

  test "post scan edits are rejected before URL registration" do
    batch = collect
    @shop.update!(name: "変更された店名")
    target = batch.targets.find_by!(shop_id: @shop.id)
    post review_target_admin_hotpepper_api_batch_path(batch, target_id: target.id, format: :json), headers: @headers, params: { match_id: target.matches.first.id, decision: "register" }
    assert_response :unprocessable_entity
    assert_nil @shop.reload.hotpepper_url
  end

  test "empty results stay unconfirmed and completed targets are not refetched on resume" do
    batch = collect([])
    target = batch.targets.find_by!(shop_id: @shop.id)
    assert_equal "unmatched", target.classification
    assert_nil @shop.reload.hotpepper_url
    execution = batch.executions.sole
    execution.update!(state: "queued")
    factory = ->(_shop) { raise "must not fetch completed targets" }
    HotpepperApi::Importer.new(batch, execution, execution.run_token, client_factory: factory).call
    assert_equal "ready", batch.reload.state
  end

  test "missing key does not create a batch" do
    ENV.delete("HOTPEPPER_API_KEY")
    assert_no_difference("HotpepperApiBatch.count") { post admin_hotpepper_api_batches_path, headers: @headers }
    assert_response :see_other
  end

  test "other-store URL conflicts leave work list" do
    batch = collect
    Shop.create!(name: "他店舗", address: "大阪府大阪市北区梅田8-9-1", genre: "居酒屋", approved: true, last_confirmed_on: Date.current, hotpepper_url: records.first.dig("urls", "pc"))
    target = batch.targets.find_by!(shop_id: @shop.id)
    post review_target_admin_hotpepper_api_batch_path(batch, target_id: target.id, format: :json), headers: @headers, params: { match_id: target.matches.first.id, decision: "register" }
    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["remove_from_list"]
    assert_equal "url_conflict", target.reload.state
    assert_nil @shop.reload.hotpepper_url
  end
  test "processing result screen works before API returns" do
    post admin_hotpepper_api_batches_path, headers: @headers, params: { trial_mode: "1" }
    batch = HotpepperApiBatch.order(:id).last
    batch.targets.create!(shop_id: @shop.id, shop_snapshot: HotpepperApi::Snapshot.call(@shop))
    get admin_hotpepper_api_batch_path(batch), headers: @headers
    assert_response :success
    assert_select "section[data-target-shop='#{@shop.id}']"
    assert_select "button[value='register']", count: 0
    assert_no_difference("HotpepperApiBatch.count") { post admin_hotpepper_api_batches_path, headers: @headers }
  end

  test "later edits are preserved when undo conflicts" do
    batch = collect
    target = register(batch)
    @shop.update!(name: "登録後の編集")
    post review_target_admin_hotpepper_api_batch_path(batch, target_id: target.id, format: :json), headers: @headers, params: { match_id: target.matches.first.id, decision: "undo" }
    assert_response :unprocessable_entity
    assert_equal "rollback_conflict", target.reload.state
    assert_equal "登録後の編集", @shop.reload.name
    assert @shop.hotpepper_url.present?
  end

  test "API wait releases database connection lease outside a transaction" do
    batch = collect([])
    execution = batch.executions.sole
    importer = HotpepperApi::Importer.new(batch, execution, execution.run_token)
    pool = ActiveRecord::Base.connection_pool
    released = false
    lease = Struct.new(:transaction_open?).new(false)
    pool.stub(:active_connection?, lease) do
      pool.stub(:release_connection, -> { released = true }) { importer.release_connection }
    end
    assert released
    released = false
    lease = Struct.new(:transaction_open?).new(true)
    pool.stub(:active_connection?, lease) do
      pool.stub(:release_connection, -> { released = true }) { importer.release_connection }
    end
    assert_not released, "caller transaction must stay pinned"
  end

end
