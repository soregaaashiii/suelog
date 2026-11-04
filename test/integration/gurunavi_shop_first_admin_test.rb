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
  test "CSV candidates precede missing candidates and each group sorts by non bot accesses" do
    shops = 3.times.map { |i| Shop.create!(name: "順序確認店#{i}", address: "大阪府大阪市北区中津#{i + 5}-1-1", genre: "居酒屋", last_confirmed_on: Date.current, approved: true) }
    batch = upload([@shop, shops[0]].map.with_index { |shop, i| [shop.name, "https://r.gnavi.co.jp/order#{i}/", shop.address, "", "", ""] })
    batch.targets.where(shop_id: shops.drop(1).map(&:id)).each { |target| target.matches.destroy_all }
    [ [@shop, 1], [shops[0], 3], [shops[1], 10], [shops[2], 5] ].each do |shop, count|
      count.times { PageView.create!(shop: shop, path: "/shops/#{shop.id}", is_bot: nil) }
    end
    20.times { PageView.create!(shop: @shop, path: "/shops/#{@shop.id}", is_bot: true) }
    get admin_gurunavi_csv_batch_path(batch), headers: @headers
    assert_response :success
    assert_select "section[data-target-shop]" do |sections|
      assert_equal [shops[0].id, @shop.id, shops[1].id, shops[2].id].map(&:to_s), sections.map { |node| node["data-target-shop"] }
    end
    get admin_gurunavi_csv_batch_path(batch, q: @shop.name), headers: @headers
    assert_response :success
    assert_select "section[data-target-shop]", count: 1
    assert_nil @shop.reload.gurunavi_url
  end
  test "one click registration undo and switching candidates keep an audit trail" do
    batch = upload([
      [@shop.name, "https://r.gnavi.co.jp/quickone/", @shop.address, "", "", ""],
      [@shop.name, "https://r.gnavi.co.jp/quicktwo/", @shop.address, "", "", ""]
    ])
    target = batch.targets.sole
    first, second = target.matches.order(:id).to_a
    get admin_gurunavi_csv_batch_path(batch), headers: @headers
    assert_select "button[name='decision'][value='register']", count: 2
    assert_select "input[disabled]", count: 0
    post review_target_admin_gurunavi_csv_batch_path(batch, target_id: target.id), headers: @headers, params: { match_id: first.id, decision: "register", page: 2, q: "test" }
    assert_response :see_other
    assert_includes response.location, "#shop-#{@shop.id}"
    assert_includes response.location, "page=2"
    assert_equal "https://r.gnavi.co.jp/quickone/", @shop.reload.gurunavi_url
    assert_equal "applied", first.reload.state
    get admin_gurunavi_csv_batch_path(batch), headers: @headers
    assert_select "section[data-target-shop]", count: 0
    assert_includes response.body, "登録済み（1店舗）"
    get admin_gurunavi_csv_batch_path(batch, classification: "review"), headers: @headers
    assert_select "section[data-target-shop]", count: 0
    get admin_gurunavi_csv_batch_path(batch, classification: "registered"), headers: @headers
    assert_select "section[data-target-shop]", count: 1
    assert_select "button", text: "取り消す", count: 1
    post review_target_admin_gurunavi_csv_batch_path(batch, target_id: target.id), headers: @headers, params: { match_id: first.id, decision: "undo" }
    assert_nil @shop.reload.gurunavi_url
    assert_equal "rolled_back", first.reload.state
    get admin_gurunavi_csv_batch_path(batch, classification: "registered"), headers: @headers
    assert_select "section[data-target-shop]", count: 0
    get admin_gurunavi_csv_batch_path(batch), headers: @headers
    assert_select "section[data-target-shop]", count: 1
    post review_target_admin_gurunavi_csv_batch_path(batch, target_id: target.id), headers: @headers, params: { match_id: second.id, decision: "register" }
    assert_equal "https://r.gnavi.co.jp/quicktwo/", @shop.reload.gurunavi_url
    assert_equal "applied", second.reload.state
    assert_equal 2, batch.events.where(action: "applied").count
    assert_equal 1, batch.events.where(action: "rolled_back").count
  end
  test "quick operations reject stale data and protect subsequent changes" do
    batch = upload
    target = batch.targets.sole
    match = target.matches.sole
    @shop.update!(name: "変更された店名")
    post review_target_admin_gurunavi_csv_batch_path(batch, target_id: target.id), headers: @headers, params: { match_id: match.id, decision: "register" }
    assert_nil @shop.reload.gurunavi_url
    post review_target_admin_gurunavi_csv_batch_path(batch, target_id: target.id), headers: @headers, params: { match_id: match.id, decision: "refresh" }
    post review_target_admin_gurunavi_csv_batch_path(batch, target_id: target.id), headers: @headers, params: { match_id: match.id, decision: "register" }
    assert_equal "applied", match.reload.state
    @shop.update!(gurunavi_url: "https://r.gnavi.co.jp/laterchange/")
    post review_target_admin_gurunavi_csv_batch_path(batch, target_id: target.id), headers: @headers, params: { match_id: match.id, decision: "undo" }
    assert_equal "https://r.gnavi.co.jp/laterchange/", @shop.reload.gurunavi_url
    assert_equal "rollback_conflict", match.reload.state
    other = upload
    post review_target_admin_gurunavi_csv_batch_path(batch, target_id: target.id), headers: @headers, params: { match_id: other.targets.sole.matches.sole.id, decision: "register" }
    assert_response :not_found
  end
  test "historical registered and skipped targets leave the work list and pages clamp" do
    batch = upload
    target = batch.targets.sole
    target.matches.sole.update!(state: "skipped")
    assert_equal [target.id], batch.targets.registered.pluck(:id)
    get admin_gurunavi_csv_batch_path(batch), headers: @headers
    assert_select "section[data-target-shop]", count: 0
    get admin_gurunavi_csv_batch_path(batch, classification: "registered", page: 99), headers: @headers
    assert_select "section[data-target-shop]", count: 1
    assert_includes response.body, "1 / 1ページ"
    target.matches.sole.update!(state: "pending")
    target.update!(classification: "registered")
    assert_equal [target.id], batch.targets.registered.pluck(:id)
    target.update!(classification: "review", state: "rollback_conflict")
    assert_equal [target.id], batch.targets.registered.pluck(:id)
  end
  test "inline JSON registration and undo return results without redirects" do
    batch = upload
    target = batch.targets.sole
    match = target.matches.sole
    get admin_gurunavi_csv_batch_path(batch), headers: @headers
    assert_select "[data-controller='csv-registration']", count: 1
    post review_target_admin_gurunavi_csv_batch_path(batch, target_id: target.id), headers: @headers.merge("ACCEPT" => "application/json"), params: { match_id: match.id, decision: "register" }
    assert_response :success
    assert response.parsed_body["success"]
    assert_equal target.shop_id, response.parsed_body["shop_id"]
    assert_nil response.headers["Location"]
    assert_equal "applied", match.reload.state
    post review_target_admin_gurunavi_csv_batch_path(batch, target_id: target.id), headers: @headers.merge("ACCEPT" => "application/json"), params: { match_id: match.id, decision: "undo" }
    assert_response :success
    assert response.parsed_body["success"]
    assert_nil @shop.reload.gurunavi_url
    @shop.update!(name: "更新された店舗")
    post review_target_admin_gurunavi_csv_batch_path(batch, target_id: target.id), headers: @headers.merge("ACCEPT" => "application/json"), params: { match_id: match.id, decision: "register" }
    assert_response :unprocessable_entity
    assert_equal false, response.parsed_body["success"]
    assert_includes response.parsed_body["message"], "更新"
    assert_nil response.headers["Location"]
  end
  test "exclude means every candidate for this shop and restore returns the whole shop" do
    other_shop = Shop.create!(name: "別の公開店", address: "大阪府大阪市北区中津5-3-2", genre: "居酒屋", last_confirmed_on: Date.current, approved: true)
    batch = upload([
      [@shop.name, "https://r.gnavi.co.jp/excludeone/", @shop.address, "", "", ""],
      [@shop.name, "https://r.gnavi.co.jp/excludetwo/", @shop.address, "", "", ""],
      [other_shop.name, "https://r.gnavi.co.jp/excludeother/", other_shop.address, "", "", ""]
    ])
    target = batch.targets.find_by!(shop_id: @shop.id)
    other = batch.targets.find_by!(shop_id: other_shop.id)
    original = other.matches.pluck(:id, :state).to_h
    assert_operator target.matches.count, :>=, 2
    post review_target_admin_gurunavi_csv_batch_path(batch, target_id: target.id), headers: @headers.merge("ACCEPT" => "application/json"), params: { decision: "exclude", match_id: target.matches.first.id }
    assert_response :success
    assert response.parsed_body["success"]
    assert_equal ["excluded"], target.matches.distinct.pluck(:state)
    assert_equal "excluded", target.reload.state
    assert_nil target.selected_match_id
    assert_equal original, other.matches.pluck(:id, :state).to_h
    assert_nil @shop.reload.gurunavi_url
    get admin_gurunavi_csv_batch_path(batch), headers: @headers
    assert_select "section[data-target-shop='#{@shop.id}']", count: 0
    assert_includes response.body, "除外済み（1店舗）"
    get admin_gurunavi_csv_batch_path(batch, classification: "excluded"), headers: @headers
    assert_select "section[data-target-shop='#{@shop.id}']", count: 1
    assert_select "button[value='restore']", count: 1
    assert_select "button[value='register']", count: 0
    post review_target_admin_gurunavi_csv_batch_path(batch, target_id: target.id), headers: @headers.merge("ACCEPT" => "application/json"), params: { decision: "restore" }
    assert_response :success
    assert_equal ["pending"], target.matches.distinct.pluck(:state)
    get admin_gurunavi_csv_batch_path(batch), headers: @headers
    assert_select "section[data-target-shop='#{@shop.id}']", count: 1
    assert_equal 1, batch.events.where(action: "exclude").count
    assert_equal 1, batch.events.where(action: "restore").count
  end
  test "work list only has three main tabs and a name address search with no state filter" do
    batch = upload
    get admin_gurunavi_csv_batch_path(batch, state: "excluded", q: @shop.name), headers: @headers
    assert_response :success
    assert_select "select[name='state']", count: 0
    assert_select "select[name='classification']", count: 0
    assert_select "input[name='state']", count: 0
    assert_select "form[method='get'] input[name='classification'][value='']", count: 1
    assert_select "form[method='get'] input[name='q']", count: 1
    assert_select "[data-csv-registration-counts] > a", count: 3
    assert_select "section[data-target-shop='#{@shop.id}']", count: 1
    assert_select "a[aria-current='page']", text: /未登録/
    get admin_gurunavi_csv_batch_path(batch, classification: "excluded", q: "店"), headers: @headers
    assert_select "input[name='classification'][value='excluded']", count: 1
    assert_select "a[aria-current='page']", text: /除外済み/
  end
  test "keyboard shortcut is visible for work lists only" do
    batch = upload
    get admin_gurunavi_csv_batch_path(batch), headers: @headers
    assert_select "[data-csv-shortcut-button]", count: 1
    assert_select "[data-action*='keydown@window->csv-registration#registerFirst']", count: 1
    %w[registered excluded invalid].each do |classification|
      get admin_gurunavi_csv_batch_path(batch, classification: classification), headers: @headers
      assert_response :success
      assert_select "[data-csv-shortcut-button]", count: 0
    end
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
