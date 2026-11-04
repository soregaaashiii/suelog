require "test_helper"
require "csv"

class GurunaviShopFirstAdminTest < ActionDispatch::IntegrationTest
  setup do
    credentials = Rails.root.join("app/controllers/admin/base_controller.rb").read.match(/name: "([^"]+)", password: "([^"]+)"/)
    @headers = { "HTTP_AUTHORIZATION"=>ActionController::HttpAuthentication::Basic.encode_credentials(credentials[1], credentials[2]) }
    Geocoder.configure(lookup: :test)
    Geocoder::Lookup::Test.set_default_stub([])
    @shop = Shop.create!(name: "公開CSVカフェ", address: "大阪府大阪市北区梅田1-2-3 第1ビル2F", genre: "居酒屋", last_confirmed_on: Date.current, approved: true)
  end
  def upload(entries = nil)
    entries ||= [ [ @shop.name, "https://r.gnavi.co.jp/store0001/", @shop.address, "17:00", "飲食", "カフェ" ] ]
    bytes = CSV.generate { |csv| csv << GurunaviCsv::Importer::HEADERS; entries.each { |entry| csv << entry } }.encode(Encoding::Windows_31J)
    Tempfile.create([ "shop-first", ".csv" ]) do |file|
      file.binmode; file.write(bytes); file.flush
      post admin_gurunavi_csv_batches_path, headers: @headers, params: { file: Rack::Test::UploadedFile.new(file.path, "text/csv", true), trial_mode: "1", area_filter: "大阪市" }
    end
    assert_response :see_other
    batch = GurunaviCsvBatch.order(:id).last
    assert batch.shop_first?
    execution = batch.executions.sole
    GurunaviCsvJob.perform_now(execution.id, execution.run_token)
    assert_equal "ready", batch.reload.state, batch.message
    batch
  end
  test "default upload lists Suelog shops not CSV only restaurants and applies after confirmation" do
    batch = upload([ [ @shop.name, "https://r.gnavi.co.jp/store0001/", @shop.address, "", "", "" ], [ "CSV専用レストランZZ999", "https://r.gnavi.co.jp/sourceonly/", "大阪府大阪市北区中津8-9-1", "", "", "" ] ])
    get admin_gurunavi_csv_batch_path(batch), headers: @headers
    assert_response :success
    assert_select "section[data-target-shop]", count: 1
    assert_includes response.body, "対象：吸えログ 1店舗"
    assert_not_includes response.body, "CSV専用レストランZZ999"
    assert_select "a[target='_blank'][href='https://r.gnavi.co.jp/store0001/']", count: 1
    assert_nil @shop.reload.gurunavi_url
    get admin_gurunavi_csv_batches_path, headers: @headers
    assert_response :success
    assert_includes response.body, "吸えログ店舗が起点"
    post apply_admin_gurunavi_csv_batch_path(batch), headers: @headers, params: { mode: "all_ready", reviewed: "1" }
    execution = batch.executions.order(:id).last
    assert_equal [ batch.targets.sole.matches.sole.id ], execution.selection
    GurunaviCsvJob.perform_now(execution.id, execution.run_token)
    assert_equal "applied", batch.targets.sole.reload.state
    assert_equal "https://r.gnavi.co.jp/store0001/", @shop.reload.gurunavi_url
    post rollback_admin_gurunavi_csv_batch_path(batch), headers: @headers, params: { mode: "all_applied", reviewed: "1" }
    execution = batch.executions.order(:id).last
    GurunaviCsvJob.perform_now(execution.id, execution.run_token)
    assert_nil @shop.reload.gurunavi_url
    assert_equal "rolled_back", batch.targets.sole.reload.state
  end
  test "missing CSV candidates still show Suelog name address and can be held or assigned a CSV line" do
    batch = upload([ [ "全く別の店", "https://r.gnavi.co.jp/other0001/", "大阪府大阪市北区中津8-9-1", "", "", "" ] ])
    target = batch.targets.sole
    get admin_gurunavi_csv_batch_path(batch, classification: "unmatched"), headers: @headers
    assert_select "section[data-target-shop='#{@shop.id}']", count: 1
    assert_includes response.body, @shop.name
    assert_includes response.body, @shop.address
    assert_includes response.body, "CSV内に候補なし"
    assert_not_includes response.body, "照合先なし"
    post review_target_admin_gurunavi_csv_batch_path(batch, target_id: target.id), headers: @headers, params: { decision: "hold" }
    assert_equal "held", target.reload.state
    post review_target_admin_gurunavi_csv_batch_path(batch, target_id: target.id), headers: @headers, params: { decision: "add", line_number: 2 }
    match = target.matches.sole
    post review_target_admin_gurunavi_csv_batch_path(batch, target_id: target.id), headers: @headers, params: { decision: "confirm", match_id: match.id }
    assert_equal "confirmed", target.reload.state
    assert_nil @shop.reload.gurunavi_url
  end
  test "pagination counts shops even when candidates are absent or multiple" do
    52.times { |i| Shop.create!(name: "候補のない公開店#{i}", address: "大阪府大阪市北区中津9-#{i + 1}-1", genre: "居酒屋", last_confirmed_on: Date.current, approved: true) }
    batch = upload([])
    assert_equal 53, batch.targets.count
    get admin_gurunavi_csv_batch_path(batch, page: 1), headers: @headers
    assert_select "section[data-target-shop]", count: 50
    assert_includes response.body, "CSV内に候補なし（53店舗）"
    get admin_gurunavi_csv_batch_path(batch, page: 2), headers: @headers
    assert_select "section[data-target-shop]", count: 3
    get admin_gurunavi_csv_batch_path(batch, q: @shop.name), headers: @headers
    assert_select "section[data-target-shop]", count: 1
  end
  test "reusing a historical CSV preserves old audit and confirmation data" do
    batch = upload
    batch.update!(matching_basis: "csv")
    batch.events.create!(action: "old_audit", payload: { preserved: true })
    get admin_gurunavi_csv_batch_path(batch), headers: @headers
    assert_includes response.body, "旧仕様の履歴"
    post rematch_admin_gurunavi_csv_batch_path(batch), headers: @headers
    fresh = GurunaviCsvBatch.order(:id).last
    assert_not_equal batch.id, fresh.id
    assert fresh.shop_first?
    assert_equal batch.sha256, fresh.sha256
    assert_equal batch.source_bytes, fresh.source_bytes
    assert batch.events.where(action: "old_audit").exists?
    assert_equal 1, batch.targets.count
    execution = fresh.executions.sole
    GurunaviCsvJob.perform_now(execution.id, execution.run_token)
    assert_equal 1, fresh.targets.count
    assert_nil @shop.reload.gurunavi_url
  end
  test "review cannot reference another target or another batch" do
    batch = upload
    other = upload
    target = batch.targets.sole
    post review_target_admin_gurunavi_csv_batch_path(batch, target_id: target.id), headers: @headers, params: { decision: "confirm", match_id: other.targets.sole.matches.sole.id }
    assert_response :not_found
    assert_equal "pending", target.reload.state
    post review_row_admin_gurunavi_csv_batch_path(batch, row_id: batch.rows.sole.id), headers: @headers, params: { decision: "confirm", match_id: target.matches.sole.id }
    assert_response :see_other
    assert_equal "pending", target.reload.state
  end
end
