require "test_helper"

class AffiliateRegistrationContractTest < ActionDispatch::IntegrationTest
  setup do
    credentials = Rails.root.join("app/controllers/admin/base_controller.rb").read.match(/name: "([^"]+)", password: "([^"]+)"/)
    @headers = { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(credentials[1], credentials[2]) }
    Geocoder.configure(lookup: :test)
    Geocoder::Lookup::Test.set_default_stub([])
    @shop = Shop.create!(name: "共通仕様テスト店", address: "大阪府大阪市北区梅田1-2-3", genre: "居酒屋", approved: true, last_confirmed_on: Date.current)
  end

  [ [ "gurunavi_csv", "GurunaviCsv", "gurunavi", "https://r.gnavi.co.jp/contract1/" ], [ "hotpepper_api", "HotpepperApi", "hotpepper", "https://www.hotpepper.jp/strJ003451218/" ] ].each do |prefix, namespace, provider, url|
    test "#{provider} uses shared hold register undo contract" do
      batch = "#{namespace}Batch".constantize.create!(filename: "contract", sha256: "test", source_bytes: "", matching_basis: "shop", state: "ready")
      snapshot = "#{namespace}::Snapshot".constantize.call(@shop)
      row = batch.rows.create!(line_number: 2, csv_name: @shop.name, csv_address: @shop.address, csv_url: url, canonical_url: url)
      target = batch.targets.create!(shop_id: @shop.id, shop_snapshot: snapshot, classification: "bulk", confidence: 400)
      match = target.matches.create!("#{prefix}_row_id" => row.id, shop_id: @shop.id, shop_snapshot: snapshot, classification: "bulk", confidence: 400)
      action = public_send("review_target_admin_#{prefix}_batch_path", batch, target_id: target.id, format: :json)
      post action, headers: @headers, params: { decision: "hold" }
      assert_response :success
      assert_equal "held", target.reload.state
      assert_not "#{namespace}Target".constantize.unregistered.exists?(target.id)
      post action, headers: @headers, params: { decision: "restore" }
      assert_response :success
      assert_equal "pending", target.reload.state
      # Another provider's registration and unrelated shop edits must not invalidate this candidate.
      other_provider = provider == "gurunavi" ? "hotpepper" : "gurunavi"
      other_url = provider == "gurunavi" ? "https://www.hotpepper.jp/strJ003451219/" : "https://r.gnavi.co.jp/otherstore/"
      @shop.update!("#{other_provider}_url" => other_url, note: "照合後のメモ変更")
      @shop.update_columns(updated_at: 1.minute.from_now)
      post action, headers: @headers, params: { decision: "register", match_id: match.id }
      assert_response :success
      assert_equal "applied", target.reload.state
      assert_equal url, @shop.reload.public_send("#{provider}_url")
      get public_send("admin_#{prefix}_batch_path", batch, classification: "registered"), headers: @headers
      assert_response :success
      assert_select "[data-registration-spec='shared']"
      assert_select "section[data-target-shop='#{@shop.id}'] input[name='decision'][value='undo']"
      post action, headers: @headers, params: { decision: "undo", match_id: match.id }
      assert_response :success
      assert_nil @shop.reload.public_send("#{provider}_url")
      assert_equal "rolled_back", target.reload.state
      assert_equal other_url, @shop.public_send("#{other_provider}_url")
    end
  end
end
