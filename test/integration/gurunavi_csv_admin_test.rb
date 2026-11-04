require "test_helper"
require "csv"

class GurunaviCsvAdminTest < ActionDispatch::IntegrationTest
  setup do
    configuration = Rails.root.join("app/controllers/admin/base_controller.rb").read
    credentials = configuration.match(/name: "([^"]+)", password: "([^"]+)"/)
    @headers = { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(credentials[1], credentials[2]) }
    Geocoder.configure(lookup: :test)
    Geocoder::Lookup::Test.set_default_stub([])
    @shop = Shop.create!(name: "CSV確認カフェ", address: "大阪府大阪市北区梅田1-2-3 第1ビル2F", genre: "居酒屋", last_confirmed_on: Date.current)
  end
  def create_upload(entries = nil, trial: "1")
    entries ||= [ [ @shop.name, "https://r.gnavi.co.jp/admin0001/", @shop.address, "17:00", "飲食", "カフェ" ] ]
    bytes = CSV.generate { |csv| csv << GurunaviCsv::Importer::HEADERS; entries.each { |entry| csv << entry } }.encode(Encoding::Windows_31J)
    Tempfile.create([ "shoplist", ".csv" ]) do |file|
      file.binmode
      file.write(bytes)
      file.flush
      upload = Rack::Test::UploadedFile.new(file.path, "text/csv", true)
      post admin_gurunavi_csv_batches_path, headers: @headers, params: { file: upload, trial_mode: trial, area_filter: "大阪市" }
    end
    assert_response :see_other
    batch = GurunaviCsvBatch.order(:id).last
    batch.update!(matching_basis: "csv") # Preserve regression coverage for historical imports.
    execution = batch.executions.sole
    GurunaviCsvJob.perform_now(execution.id, execution.run_token)
    assert_equal "ready", batch.reload.state, batch.message
    batch
  end
  test "upload and preview never change shops and registration requires explicit confirmation" do
    assert_difference("GurunaviCsvBatch.count", 1) { @batch = create_upload }
    assert_nil @shop.reload.gurunavi_url
    get admin_gurunavi_csv_batch_path(@batch), headers: @headers
    assert_response :success
    assert_select "form#bulk-apply", count: 1
    assert_select "[data-csv-line='2']", count: 1
    assert_select "a[target='_blank'][href='https://r.gnavi.co.jp/admin0001/']", count: 1
    post apply_admin_gurunavi_csv_batch_path(@batch), headers: @headers, params: { mode: "all_ready" }
    assert_response :see_other
    assert_equal 1, @batch.executions.count
    post apply_admin_gurunavi_csv_batch_path(@batch), headers: @headers, params: { mode: "all_ready", reviewed: "1" }
    assert_response :see_other
    execution = @batch.executions.order(:id).last
    assert_equal "queued", execution.state
    assert_nil @shop.reload.gurunavi_url
    GurunaviCsvJob.perform_now(execution.id, execution.run_token)
    assert_equal "https://r.gnavi.co.jp/admin0001/", @shop.reload.gurunavi_url
    assert_equal GurunaviAffiliateUrlBuilder.call(@shop.gurunavi_url), @shop.gurunavi_affiliate_url
    post rollback_admin_gurunavi_csv_batch_path(@batch), headers: @headers, params: { mode: "all_applied", reviewed: "1" }
    execution = @batch.executions.order(:id).last
    GurunaviCsvJob.perform_now(execution.id, execution.run_token)
    assert_nil @shop.reload.gurunavi_url
    get admin_gurunavi_csv_batch_path(@batch), headers: @headers
    assert_response :success
    assert_includes response.body, "取り消し済み"
  end

  test "review candidates persist hold exclusion confirmation and show escaped differences" do
    batch = create_upload([ [ @shop.name + "<script>alert(1)</script>", "https://r.gnavi.co.jp/admin0001/", @shop.address, "17:00", "飲食", "カフェ" ] ])
    row, match = batch.rows.sole, batch.rows.sole.matches.sole
    assert_equal "review", row.classification
    get admin_gurunavi_csv_batch_path(batch, classification: "review", q: "CSV確認"), headers: @headers
    assert_response :success
    assert_select "mark", minimum: 1
    assert_not_includes response.body, "<script>alert(1)</script>"
    assert_includes response.body, "&lt;script&gt;"
    %w[hold exclude confirm].each do |decision|
      post review_row_admin_gurunavi_csv_batch_path(batch, row_id: row.id), headers: @headers, params: { match_id: match.id, decision: decision }
      assert_response :see_other
    end
    assert_equal "confirmed", match.reload.state
    assert_nil @shop.reload.gurunavi_url
    get admin_gurunavi_csv_batch_path(batch, state: "confirmed"), headers: @headers
    assert_response :success
    assert_select "[data-csv-line='2']", count: 1
  end

  test "pagination filtering and unmatched manual candidates use only the selected batch" do
    entries = 55.times.map { |i| [ "架空CSV#{i}", "https://r.gnavi.co.jp/admin#{i.to_s.rjust(6, '0')}/", "大阪府大阪市北区中津1-#{i + 1}-1", "17:00", "飲食", "カフェ" ] }
    batch = create_upload(entries, trial: "0")
    get admin_gurunavi_csv_batch_path(batch, classification: "unmatched", page: 1), headers: @headers
    assert_response :success
    assert_select "[data-csv-line]", count: 50
    get admin_gurunavi_csv_batch_path(batch, classification: "unmatched", page: 2), headers: @headers
    assert_select "[data-csv-line]", count: 5
    row = batch.rows.order(:line_number).first
    post review_row_admin_gurunavi_csv_batch_path(batch, row_id: row.id), headers: @headers, params: { decision: "add", shop_id: @shop.id }
    assert_response :see_other
    assert_equal @shop.id, row.matches.sole.shop_id
    assert_equal "review", row.reload.classification
    assert_nil @shop.reload.gurunavi_url
    other = create_upload
    post apply_admin_gurunavi_csv_batch_path(batch), headers: @headers, params: { match_ids: other.rows.sole.matches.pluck(:id), reviewed: "1" }
    assert_equal 1, batch.executions.count
  end

  test "failed or stale executions can resume without using old tokens or overwriting shops" do
    batch = create_upload
    execution = batch.executions.sole
    execution.update!(state: "failed", message: "検証用の中断")
    batch.update!(state: "failed")
    old = execution.run_token
    post resume_admin_gurunavi_csv_batch_path(batch), headers: @headers, params: { execution_id: execution.id }
    assert_response :see_other
    assert_not_equal old, execution.reload.run_token
    GurunaviCsvJob.perform_now(execution.id, old)
    assert_equal "queued", execution.reload.state
    GurunaviCsvJob.perform_now(execution.id, execution.run_token)
    assert_equal "completed", execution.reload.state
    assert_equal "ready", batch.reload.state
    assert_equal 1, batch.rows.count
    assert_nil @shop.reload.gurunavi_url
    assert_equal "検証用の中断", batch.events.find_by!(action: "resumed").payload["previous_message"]
  end

  test "admin authentication and upload validation are enforced" do
    get admin_gurunavi_csv_batches_path
    assert_response :unauthorized
    post admin_gurunavi_csv_batches_path, headers: @headers
    assert_response :unprocessable_entity
    assert_select "input[type='file'][name='file']", count: 1
  end
end
