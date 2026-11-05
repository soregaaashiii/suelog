require "test_helper"
require "csv"

class GurunaviCsvTest < ActiveSupport::TestCase
  setup do
    Geocoder.configure(lookup: :test)
    Geocoder::Lookup::Test.set_default_stub([])
    @address = "大阪府大阪市北区梅田1-2-3 サンパーク2F"
    @shop = Shop.create!(name: "カフェ A 梅田店", address: @address, genre: "居酒屋", last_confirmed_on: Date.current, smoking_area: :all_smoking, smoking_type: :both_ok, approved: true)
    @url = "https://r.gnavi.co.jp/csv000001/"
  end
  def entry(name = @shop.name, address = @address, url = @url)
    [ name, url, address, "17:00-23:00", "飲食", "カフェ" ]
  end
  def batch_for(entries, trial: false, area: nil, bytes: nil, basis: "csv")
    bytes ||= CSV.generate { |csv| csv << GurunaviCsv::Importer::HEADERS; entries.each { |row| csv << row } }.encode(Encoding::Windows_31J)
    batch = GurunaviCsvBatch.create!(filename: "shoplist.csv", source_bytes: bytes, sha256: Digest::SHA256.hexdigest(bytes), trial_mode: trial, area_filter: area, matching_basis: basis)
    execution = batch.executions.create!(kind: "match", run_token: SecureRandom.uuid)
    GurunaviCsv::Importer.new(batch, execution, execution.run_token).call
    batch.reload
  end
  def execute(batch, kind, ids = nil)
    ids ||= GurunaviCsvMatch.where(gurunavi_csv_row_id: batch.rows.select(:id)).pluck(:id)
    execution = batch.executions.create!(kind: kind, selection: ids, total_count: ids.size, run_token: SecureRandom.uuid)
    # Call the service directly so unexpected failures are visible in tests.
    GurunaviCsv::Operations.new(execution, execution.run_token).call
    execution.reload
  end

  test "expand scans all areas beyond trial limit while preserving decisions and avoiding duplicates" do
    101.times { |i| Shop.create!(name: "全件対象#{i}", address: "大阪府大阪市北区中津#{i + 10}-1-1", genre: "居酒屋", last_confirmed_on: Date.current, approved: true) }
    tokyo = Shop.create!(name: "別エリア対象", address: "東京都新宿区新宿1-2-3", genre: "居酒屋", last_confirmed_on: Date.current, approved: true)
    Shop.create!(name: "未承認除外", address: "大阪府大阪市北区中津9-1-1", genre: "居酒屋", last_confirmed_on: Date.current, approved: false)
    batch = batch_for([entry], trial: true, area: "大阪市", basis: "shop")
    assert_equal 100, batch.targets.count
    first = batch.targets.find_by!(shop_id: @shop.id)
    match = first.matches.sole
    GurunaviCsv::TargetReview.call(first, "confirm", match: match)
    execution = batch.executions.create!(kind: "apply", selection: [match.id], run_token: SecureRandom.uuid)
    GurunaviCsv::Operations.new(execution, execution.run_token).call
    excluded = batch.targets.where.not(id: first.id).first
    GurunaviCsv::TargetReview.call(excluded, "exclude")
    2.times do
      execution = batch.executions.create!(kind: "expand", run_token: SecureRandom.uuid)
      GurunaviCsv::RefreshCandidates.new(execution, execution.run_token).call
      assert_equal "completed", execution.reload.state
      assert_equal 103, batch.targets.count
      assert_equal 103, execution.processed_count
      assert_equal "applied", first.reload.state
      assert_equal "excluded", excluded.reload.state
      assert_equal @url, @shop.reload.gurunavi_url
      assert batch.targets.exists?(shop_id: tokyo.id)
      assert_equal [match.id], first.matches.pluck(:id)
    end
    assert_not batch.reload.trial_mode?
    assert_nil batch.area_filter
    assert_equal 103, batch.target_rows
    assert_equal 1, batch.rows.count
  end
  test "broader candidates stay low confidence and never qualify for bulk registration" do
    @shop.update!(name: "カフェアオゾラ梅田")
    batch = batch_for([entry("こだわりの個室ダイニングアオゾラ梅田店")], basis: "shop")
    target = batch.targets.sole
    assert_equal "review", target.classification
    assert_equal 50, target.confidence
    assert_equal 1, target.matches.count
    assert_nil @shop.reload.gurunavi_url
    scorer = GurunaviCsv::Confidence
    assert_equal 50, scorer.score("洋食アオゾラ梅田", @address, "カフェアオゾラ梅田", @address.sub("1-2-3", "1-2-8"))
    assert_equal 0, scorer.score("洋食アオゾラ梅田", @address, "カフェアオゾラ梅田", "東京都新宿区新宿1-2-3")
    assert_equal "参考候補（低確度・要確認）", scorer.label(50)
  end
  test "confidence stages recover promotional names and aliases without automatic confirmation" do
    examples = [
      ["おでんと串 大衆酒場 だるま商店", "大阪府大阪市北区堂山町5-9 8階", "生付き750円飲み放題 おでんと串 個室酒場 だるま商店 梅田店", "大阪府大阪市北区堂山町5-9 扇会館8F"],
      ["プロント 東本町店 （PRONTO）", "大阪府大阪市中央区久太郎町1-9-29 東本町ビル", "プロント東本町店", "大阪府大阪市中央区久太郎町1-9-29"]
    ]
    examples.each do |name, address, csv_name, csv_address|
      @shop.update!(name: name, address: address)
      batch = batch_for([entry(csv_name, csv_address)], basis: "shop")
      target = batch.targets.sole
      assert_equal "review", target.classification
      assert_equal 200, target.confidence
      assert_equal 1, target.matches.count
      assert_nil @shop.reload.gurunavi_url
    end
    scorer = GurunaviCsv::Confidence
    assert_equal 400, scorer.score("プロント東本町店", @address, "プロント東本町店", @address)
    assert_equal 300, scorer.score("プロント東本町店（PRONTO）", @address, "プロント東本町店", @address)
    assert_equal 100, scorer.score("カフェA梅田店", @address, "カフェA梅田店", @address.sub("2F", "3F"))
    assert_equal 100, scorer.score("カフェA梅田店", @address, "カフェA梅田店", @address.sub("1-2-3", "1-2-9"))
    assert_equal 0, scorer.score("皆様酒場 昭和ゴールデン 大阪駅前第4ビル店", @address, "鶴亀八番 大阪駅前第4ビル店", @address)
    assert_equal 0, scorer.score("", @address, "カフェ", @address)
    assert_equal 0, scorer.score("居酒屋イロハ", @address, "全く別の焼肉屋", @address)
  end
  test "confidence refresh adds missed candidates and preserves registered excluded held and confirmed decisions" do
    batch = batch_for([entry], basis: "shop")
    target = batch.targets.sole
    original = target.matches.sole
    # Simulate a historical unmatched preview without deleting other audit records.
    original.destroy!
    target.update!(classification: "unmatched", confidence: 0)
    run = batch.executions.create!(kind: "confidence", run_token: SecureRandom.uuid)
    GurunaviCsv::RefreshCandidates.new(run, run.run_token).call
    assert_equal "completed", run.reload.state
    assert_equal 400, target.reload.confidence
    assert_equal 1, target.matches.count
    match = target.matches.sole
    GurunaviCsv::TargetReview.call(target, "exclude")
    run = batch.executions.create!(kind: "confidence", run_token: SecureRandom.uuid)
    GurunaviCsv::RefreshCandidates.new(run, run.run_token).call
    assert_equal "excluded", target.reload.state
    assert_equal [match.id], target.matches.pluck(:id)
    assert_equal "excluded", match.reload.state
    GurunaviCsv::TargetReview.call(target, "restore")
    GurunaviCsv::TargetReview.call(target, "confirm", match: match)
    run = batch.executions.create!(kind: "confidence", run_token: SecureRandom.uuid)
    GurunaviCsv::RefreshCandidates.new(run, run.run_token).call
    assert_equal "confirmed", target.reload.state
    assert_equal match.id, target.selected_match_id
    execution = batch.executions.create!(kind: "apply", selection: [match.id], run_token: SecureRandom.uuid)
    GurunaviCsv::Operations.new(execution, execution.run_token).call
    values = GurunaviCsv::Snapshot.url_values(@shop.reload)
    run = batch.executions.create!(kind: "confidence", run_token: SecureRandom.uuid)
    GurunaviCsv::RefreshCandidates.new(run, run.run_token).call
    assert_equal "applied", match.reload.state
    assert_equal values, GurunaviCsv::Snapshot.url_values(@shop.reload)
    assert_equal "applied", target.reload.state
  end
  test "shop first results contain published shops only and search the entire CSV" do
    other = @shop.dup
    other.name, other.address = "公開中でCSVにない店舗", @address.sub("1-2-3", "1-2-9")
    other.save!
    pending = @shop.dup
    pending.name, pending.address, pending.approved = "未承認店舗", @address.sub("1-2-3", "1-2-8"), false
    pending.save!
    held = @shop.dup
    held.name, held.address, held.on_hold = "保留店舗", @address.sub("1-2-3", "1-2-7"), true
    held.save!
    entries = 120.times.map { |i| entry("CSVだけの店舗#{i}", "大阪府大阪市北区中津2-#{i + 1}-1", "https://r.gnavi.co.jp/onlycsv#{i}/") }
    entries += [ entry(pending.name, pending.address, "https://r.gnavi.co.jp/pending01/"), entry(held.name, held.address, "https://r.gnavi.co.jp/held0001/"), entry ]
    batch = batch_for(entries, trial: true, area: "大阪市", basis: "shop")
    assert_equal "shop", batch.matching_basis
    assert_equal 123, batch.total_rows
    assert_equal 2, batch.target_rows
    assert_equal 2, batch.processed_rows
    assert_equal [ @shop.id, other.id ].sort, batch.targets.pluck(:shop_id).sort
    assert_equal "bulk", batch.targets.find_by!(shop_id: @shop.id).classification
    missing = batch.targets.find_by!(shop_id: other.id)
    assert_equal "unmatched", missing.classification
    assert_empty missing.matches
    assert_includes missing.reason, "CSV内に見つかりません"
    assert_nil @shop.reload.gurunavi_url
    assert_equal 124, batch.targets.find_by!(shop_id: @shop.id).matches.sole.gurunavi_csv_row.line_number
  end

  test "shop first trial limits shops instead of CSV rows and keeps global duplicates conservative" do
    104.times do |i|
      Shop.create!(name: "公開店舗#{i}", address: "大阪府大阪市北区梅田2-#{i + 1}-1", genre: "居酒屋", last_confirmed_on: Date.current, approved: true)
    end
    entries = 110.times.map { |i| entry("CSV専用#{i}", "大阪府大阪市北区中津9-#{i + 1}-1", "https://r.gnavi.co.jp/source#{i}/") }
    entries += [ entry, entry(@shop.name, @address, "https://r.gnavi.co.jp/duplicate01/") ]
    batch = batch_for(entries, trial: true, area: "大阪市北区", basis: "shop")
    assert_equal 100, batch.targets.count
    assert_equal 100, batch.target_rows
    assert_equal 112, batch.total_rows
    target = batch.targets.find_by!(shop_id: @shop.id)
    assert_equal "review", target.classification
    assert_equal 2, target.matches.count
    assert_empty target.matches.where(classification: "bulk")
    assert_equal 100, batch.targets.group(:classification).count.values.sum
  end

  test "shop first candidates confirm one CSV row per shop and apply rollback safely" do
    batch = batch_for([ entry(@shop.name, @address.sub("2F", "3F")), entry(@shop.name, @address.sub("2F", "4F"), "https://r.gnavi.co.jp/alternate01/") ], basis: "shop")
    target = batch.targets.sole
    assert_equal "review", target.classification
    first, second = target.matches.order(:id).to_a
    GurunaviCsv::TargetReview.call(target, "confirm", match: first)
    GurunaviCsv::TargetReview.call(target, "confirm", match: second)
    assert_equal "pending", first.reload.state
    assert_equal second.id, target.reload.selected_match_id
    execute(batch, "apply", [ second.id ])
    assert_equal "applied", target.reload.state
    assert_equal "https://r.gnavi.co.jp/alternate01/", @shop.reload.gurunavi_url
    execute(batch, "rollback", [ second.id ])
    assert_equal "rolled_back", target.reload.state
    assert_nil @shop.reload.gurunavi_url
  end

  test "shop first manual CSV candidates cannot bypass confirmation and reject legacy review paths" do
    batch = batch_for([ entry, entry("別店舗", @address.sub("1-2-3", "8-9-1"), "https://r.gnavi.co.jp/manual0001/") ], basis: "shop")
    target = batch.targets.sole
    original = target.matches.sole
    GurunaviCsv::TargetReview.call(target, "add", line_number: 3)
    execute(batch, "apply", [ original.id ])
    assert_nil @shop.reload.gurunavi_url
    assert_equal "conflict", target.reload.state
    assert_raises(GurunaviCsv::Review::Conflict) { GurunaviCsv::Review.call(batch.rows.first, "confirm", match: original) }
    manual = target.matches.find_by!(gurunavi_csv_row_id: batch.rows.find_by!(line_number: 3).id)
    GurunaviCsv::TargetReview.call(target, "confirm", match: manual)
    execute(batch, "apply", [ manual.id ])
    assert_equal "https://r.gnavi.co.jp/manual0001/", @shop.reload.gurunavi_url
  end

  test "shop first publication changes stale snapshots existing URLs and rollback conflicts are protected" do
    batch = batch_for([ entry ], basis: "shop")
    @shop.update!(on_hold: true)
    execute(batch, "apply")
    assert_nil @shop.reload.gurunavi_url
    assert_equal "conflict", batch.targets.sole.reload.state
    @shop.update!(on_hold: false, gurunavi_url: @url, gurunavi_affiliate_url: GurunaviAffiliateUrlBuilder.call(@url))
    existing = batch_for([], basis: "shop")
    assert_equal "registered", existing.targets.sole.classification
    assert_equal @url, @shop.reload.gurunavi_url
    @shop.update!(gurunavi_url: nil, gurunavi_affiliate_url: nil)
    batch = batch_for([ entry ], basis: "shop")
    execute(batch, "apply")
    @shop.update!(name: "照合後に店名を更新")
    execute(batch, "rollback")
    assert_equal "rollback_conflict", batch.targets.sole.reload.state
    assert_equal @url, @shop.reload.gurunavi_url
  end

  test "shop first matching never promotes name only address only branch floor or incomplete data to bulk" do
    samples = [ entry(@shop.name, @address.sub("1-2-3", "1-2-4")), entry("別店舗", @address), entry("カフェ A 難波店", @address), entry(@shop.name, @address.sub("2F", "3F")), entry(@shop.name, "大阪府大阪市北区梅田1-2-3"), entry("", @address) ]
    samples.each_with_index { |row, index| row[1] = "https://r.gnavi.co.jp/shopfirst#{index}/" }
    batch = batch_for(samples, basis: "shop")
    assert_equal "review", batch.targets.sole.classification
    assert_empty batch.targets.sole.matches.where(classification: "bulk")
    assert_equal 1, batch.rows.where(classification: "invalid").count
    assert_nil @shop.reload.gurunavi_url
  end

  test "shop first reviews remain independent for a shared CSV candidate and URL ownership is rechecked" do
    other = @shop.dup
    other.name = "カフェ A 梅田店 別館"
    other.save!
    batch = batch_for([ entry("カフェ A", @address) ], basis: "shop")
    assert_equal 2, batch.targets.count
    batch.targets.each do |target|
      assert_equal "review", target.classification
      GurunaviCsv::TargetReview.call(target, "confirm", match: target.matches.sole)
    end
    assert_equal 2, batch.targets.where(state: "confirmed").count
    execute(batch, "apply")
    assert_equal 1, batch.targets.where(state: "applied").count
    assert_equal 1, batch.targets.where(state: "url_conflict").count
    assert_equal 1, Shop.where(gurunavi_csv_url_key: @url).count
  end

  test "shop first matching reads CSV and shops in batches rather than per target" do
    entries = 200.times.map do |i|
      store = Shop.create!(name: "照合性能店舗#{i}", address: "大阪府大阪市北区梅田8-#{i + 1}-1", genre: "居酒屋", last_confirmed_on: Date.current, approved: true)
      entry(store.name, store.address, "https://r.gnavi.co.jp/batchcsv#{i}/")
    end
    queries = []
    callback = ->(*args) { sql = args.last[:sql]; queries << sql if sql.match?(/SELECT.*FROM ["`]?(shops|gurunavi_csv_rows)["`]?/i) }
    batch = nil
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { batch = batch_for(entries, basis: "shop") }
    assert_equal 201, batch.targets.count
    assert_equal 200, batch.targets.where(classification: "bulk").count
    assert_operator queries.size, :<, 20
  end

  test "CP932 postal and width parcel differences match but leave shop untouched before confirmation" do
    name = " ｶﾌｪ　Ａ　梅田店 "
    address = "〒530-0001 大阪府大阪市北区梅田一丁目２番３号 サンパーク２Ｆ"
    count = Shop.count
    batch = batch_for([ entry(name, address) ])
    row = batch.rows.sole
    assert_equal "ready", batch.state
    assert_equal "completed", batch.executions.sole.state
    assert_equal "bulk", row.classification
    assert_equal name, row.csv_name
    assert_equal address, row.csv_address
    assert_kind_of Hash, row.raw_fields
    assert_includes row.raw_row, "〒530-0001"
    assert_equal 2, row.line_number
    assert_equal @shop.id, row.matches.sole.shop_id
    assert_kind_of Hash, row.matches.sole.shop_snapshot
    assert_nil @shop.reload.gurunavi_url
    assert_nil @shop.gurunavi_affiliate_url
    assert_equal count, Shop.count
  end

  test "bounded malformed quoting is retained as invalid without repairing fields" do
    header = CSV.generate_line(GurunaviCsv::Importer::HEADERS)
    valid = CSV.generate_line(entry)
    bad = '"別店舗","https://r.gnavi.co.jp/bad000001/","大阪府大阪市北区梅田1-2-8","営業時間"注記"","飲食","カフェ"' + "\n"
    batch = batch_for([], bytes: (header + bad + valid).encode(Encoding::Windows_31J))
    assert_equal 2, batch.total_rows
    invalid = batch.rows.find_by!(line_number: 2)
    assert_equal "invalid", invalid.classification
    assert_equal bad, invalid.raw_row
    assert_includes invalid.reason, "CSVの構造が不正"
    assert_empty invalid.matches
    assert_equal "bulk", batch.rows.find_by!(line_number: 3).classification
    assert_nil @shop.reload.gurunavi_url
  end

  test "short custom Gurunavi detail paths use the existing affiliate builder" do
    batch = batch_for([ entry(@shop.name, @address, "http://r.gnavi.co.jp/ton/") ])
    assert_equal "bulk", batch.rows.sole.classification
    execute(batch, "apply")
    assert_equal "https://r.gnavi.co.jp/ton/", @shop.reload.gurunavi_url
    assert_equal GurunaviAffiliateUrlBuilder.call(@shop.gurunavi_url), @shop.gurunavi_affiliate_url
    assert_nil RestaurantUrlSearch::Provider.new("gurunavi").canonical_url("https://r.gnavi.co.jp/help/")
  end

  test "normalization preserves branch building long vowels numeric building names floors and rooms" do
    n = GurunaviCsv::Normalizer
    assert_equal n.address(@address), n.address("〒530-0001 大阪府大阪市北区梅田１丁目２番３号 サンパーク２Ｆ")
    assert_not_equal n.name("カフェ A 梅田店"), n.name("カフェ A 難波店")
    assert_not_equal n.address(@address), n.address(@address.sub("2F", "3F"))
    assert_not_equal n.address(@address), n.address(@address.sub("サンパーク", "サンパ-ク"))
    assert_not_equal n.address(@address + "201号室"), n.address(@address + "202号室")
    assert_not_equal n.address(@address.sub("サンパーク", "第1ビル")), n.address(@address.sub("サンパーク", "第2ビル"))
    assert_includes n.address(@address.sub("サンパーク", "第1-2号館")), "第1-2号館"
  end

  test "name only address only other branch and different parcels or floors are not bulk" do
    samples = [ entry(@shop.name, @address.sub("1-2-3", "1-2-4")), entry("別の飲食店", @address), entry("カフェ A 難波店", @address), entry(@shop.name, @address.sub("2F", "3F")), entry(@shop.name, "大阪府大阪市北区梅田1-2-3") ]
    samples.each_with_index { |e, index| e[1] = "https://r.gnavi.co.jp/check#{index}001/" }
    batch = batch_for(samples)
    assert_empty batch.rows.where(classification: "bulk")
    assert batch.rows.where(classification: "review").exists?
    assert_nil @shop.reload.gurunavi_url
  end

  test "duplicate CSV identities duplicate shop keys and duplicate CSV URLs require review" do
    batch = batch_for([ entry, entry("ｶﾌｪ A 梅田店", "〒530-0001 " + @address, "https://r.gnavi.co.jp/csv000002/") ])
    assert_equal [ "review" ], batch.rows.distinct.pluck(:classification)
    duplicate = @shop.dup
    duplicate.name = "ｶﾌｪ　Ａ　梅田店"
    duplicate.save!
    batch = batch_for([ entry ])
    assert_equal "review", batch.rows.sole.classification
    assert_equal 2, batch.rows.sole.matches.size
    assert_empty batch.rows.sole.matches.where(classification: "bulk")
    duplicate.destroy!
    other = @shop.dup
    other.name, other.address = "別の店舗", @address.sub("1-2-3", "1-2-8")
    other.save!
    batch = batch_for([ entry, entry(other.name, other.address, @url) ])
    assert_empty batch.rows.where(classification: "bulk")
  end

  test "registered same URLs skip different URLs and existing affiliate-only values conflict" do
    @shop.update!(gurunavi_url: "http://r.gnavi.co.jp/csv000001/?x=1", gurunavi_affiliate_url: "https://affiliate.example/old")
    batch = batch_for([ entry ])
    assert_equal "registered", batch.rows.sole.classification
    assert_equal "skipped", batch.rows.sole.matches.sole.state
    execute(batch, "apply")
    assert_equal "http://r.gnavi.co.jp/csv000001/?x=1", @shop.reload.gurunavi_url
    batch = batch_for([ entry(@shop.name, @address, "https://r.gnavi.co.jp/other0001/") ])
    assert_equal "conflict", batch.rows.sole.classification
    @shop.update!(gurunavi_url: nil, gurunavi_affiliate_url: "https://affiliate.example/keep")
    assert_equal "conflict", batch_for([ entry ]).rows.sole.classification
  end

  test "same URL owned by another shop is a conflict before matching and immediately before apply" do
    owner = @shop.dup
    owner.name = "所有店舗"
    owner.gurunavi_url = @url
    owner.save!
    assert_equal @url, owner.gurunavi_csv_url_key
    batch = batch_for([ entry ])
    assert_equal "conflict", batch.rows.sole.classification
    owner.update!(gurunavi_url: nil)
    batch = batch_for([ entry ])
    assert_equal "bulk", batch.rows.sole.classification
    owner.update!(gurunavi_url: @url)
    execute(batch, "apply")
    assert_equal "conflict", batch.rows.sole.matches.sole.state
    assert_nil @shop.reload.gurunavi_url
  end

  test "confirmed registration uses existing converter and repeated jobs or uploads are idempotent" do
    @shop.update!(tabelog_url: "https://tabelog.com/test/", tabelog_affiliate_url: "https://affiliate.example/tabelog", hotpepper_url: "https://www.hotpepper.jp/strJ001234567/", hotpepper_affiliate_url: "https://affiliate.example/hp", hide_gurunavi_booking_button: true)
    batch = batch_for([ entry ])
    match = batch.rows.sole.matches.sole
    execution = execute(batch, "apply")
    assert_equal "completed", execution.state
    assert_equal "applied", match.reload.state
    assert_equal @url, @shop.reload.gurunavi_url
    assert_equal GurunaviAffiliateUrlBuilder.call(@url), @shop.gurunavi_affiliate_url
    assert_nil match.before_values["gurunavi_url"]
    assert_equal @url, match.after_values["gurunavi_url"]
    assert @shop.hide_gurunavi_booking_button?
    assert_equal "https://affiliate.example/tabelog", @shop.tabelog_affiliate_url
    assert_equal "https://affiliate.example/hp", @shop.hotpepper_affiliate_url
    version = @shop.updated_at
    GurunaviCsvJob.perform_now(execution.id, execution.run_token)
    execute(batch, "apply")
    assert_equal version, @shop.reload.updated_at
    assert_equal 1, batch.events.where(action: "applied").count
    assert_equal "registered", batch_for([ entry ]).rows.sole.classification
  end

  test "data changed after preview or registered by another batch cannot be overwritten" do
    batch1, batch2 = batch_for([ entry ]), batch_for([ entry ])
    execute(batch1, "apply")
    execute(batch2, "apply")
    assert_equal "conflict", batch2.rows.sole.matches.sole.state
    assert_nil batch2.rows.sole.matches.sole.applied_at
    assert_equal @url, @shop.reload.gurunavi_url
    @shop.update!(gurunavi_url: nil, gurunavi_affiliate_url: nil)
    batch3 = batch_for([ entry ])
    @shop.update!(address: @address.sub("2F", "4F"))
    execute(batch3, "apply")
    assert_equal "conflict", batch3.rows.sole.matches.sole.state
    assert_nil @shop.reload.gurunavi_url
  end

  test "a new duplicate identity after preview becomes a conflict at registration" do
    batch = batch_for([ entry ])
    duplicate = @shop.dup
    duplicate.name = "ｶﾌｪ　Ａ　梅田店"
    duplicate.save!
    execute(batch, "apply")
    assert_equal "conflict", batch.rows.sole.matches.sole.state
    assert_nil @shop.reload.gurunavi_url
  end

  test "manual confirmation exclusion hold and explicit conflict replacement preserve review history" do
    @shop.update!(gurunavi_url: "https://r.gnavi.co.jp/before001/", gurunavi_affiliate_url: "https://affiliate.example/before")
    batch = batch_for([ entry ])
    row, match = batch.rows.sole, batch.rows.sole.matches.sole
    GurunaviCsv::Review.call(row, "hold", match: match)
    assert_equal "held", row.reload.state
    GurunaviCsv::Review.call(row, "exclude", match: match)
    assert_equal "excluded", match.reload.state
    assert_raises(GurunaviCsv::Review::Conflict) { GurunaviCsv::Review.call(row, "confirm", match: match) }
    GurunaviCsv::Review.call(row, "confirm", match: match, allow_replace: true)
    assert_equal "confirmed", match.reload.state
    assert_equal "https://r.gnavi.co.jp/before001/", @shop.reload.gurunavi_url
    execute(batch, "apply")
    assert_equal @url, @shop.reload.gurunavi_url
    execute(batch, "rollback")
    assert_equal "https://r.gnavi.co.jp/before001/", @shop.reload.gurunavi_url
    assert_equal "https://affiliate.example/before", @shop.gurunavi_affiliate_url
    assert_equal "rolled_back", match.reload.state
    assert_equal %w[hold exclude confirm], batch.events.where(action: %w[hold exclude confirm]).order(:id).pluck(:action)
  end

  test "rollback restores only this import and refuses subsequent changes even when values return" do
    batch = batch_for([ entry ])
    execute(batch, "apply")
    execute(batch, "rollback")
    assert_nil @shop.reload.gurunavi_url
    assert_nil @shop.gurunavi_affiliate_url
    execute(batch, "rollback")
    assert_equal 1, batch.events.where(action: "rolled_back").count
    batch2 = batch_for([ entry ])
    execute(batch2, "apply")
    value = @shop.reload.gurunavi_affiliate_url
    travel 1.second do
      @shop.update!(gurunavi_affiliate_url: "https://affiliate.example/later")
      @shop.update!(gurunavi_affiliate_url: value)
    end
    execute(batch2, "rollback")
    assert_equal "rollback_conflict", batch2.rows.sole.matches.sole.state
    assert_equal value, @shop.reload.gurunavi_affiliate_url
    assert_equal @url, @shop.gurunavi_url
  end

  test "audit failure after shop update rolls back values before marking a conflict" do
    batch = batch_for([ entry ])
    original = GurunaviCsv::Operations.instance_method(:event)
    GurunaviCsv::Operations.define_method(:event) do |match, action, payload|
      if action == "applied"
        event = GurunaviCsvEvent.new
        event.errors.add(:base, "検証用の履歴保存失敗")
        raise ActiveRecord::RecordInvalid, event
      end
      original.bind_call(self, match, action, payload)
    end
    execute(batch, "apply")
    assert_nil @shop.reload.gurunavi_url
    assert_nil @shop.gurunavi_affiliate_url
    assert_equal "conflict", batch.rows.sole.matches.sole.state
    assert_nil batch.rows.sole.matches.sole.applied_at
  ensure
    GurunaviCsv::Operations.define_method(:event, original) if original
  end

  test "trial area limit is 100 but duplicates anywhere in CSV still prevent bulk" do
    entries = 105.times.map do |i|
      name, address = "CSV検証店舗#{i}", "大阪府大阪市北区梅田1-#{i + 10}-1"
      Shop.create!(name: name, address: address, genre: "居酒屋", last_confirmed_on: Date.current)
      entry(name, address, "https://r.gnavi.co.jp/trial#{i.to_s.rjust(6, '0')}/")
    end
    entries << entries.first.dup
    batch = batch_for(entries, trial: true, area: "大阪市北区")
    assert_equal 106, batch.total_rows
    assert_equal 100, batch.target_rows
    assert_equal 100, batch.processed_rows
    assert_equal 6, batch.rows.where(classification: "out_of_scope").count
    assert_equal "review", batch.rows.order(:line_number).first.classification
    assert_nil @shop.reload.gurunavi_url
  end

  test "invalid missing and quoted multiline rows retain physical line numbers" do
    rows = [ entry("カフェ\n改行", @address), entry("", @address), entry(@shop.name, "〒530-0001"), entry(@shop.name, @address, "https://r.gnavi.co.jp/area/osaka/") ]
    batch = batch_for(rows)
    assert_equal [ 2, 4, 5, 6 ], batch.rows.order(:line_number).pluck(:line_number)
    assert_equal 3, batch.rows.where(classification: "invalid").count
    assert_nil @shop.reload.gurunavi_url
  end

  test "bad CP932 bytes and malformed CSV fail without replacement or shop writes" do
    good = CSV.generate { |csv| csv << GurunaviCsv::Importer::HEADERS; csv << entry }.encode(Encoding::Windows_31J).b
    [ good + "\x81\x00\n".b, good + '"unclosed'.b ].each do |bytes|
      batch = GurunaviCsvBatch.create!(filename: "shoplist.csv", sha256: Digest::SHA256.hexdigest(bytes), source_bytes: bytes)
      execution = batch.executions.create!(kind: "match", run_token: SecureRandom.uuid)
      GurunaviCsvJob.perform_now(execution.id, execution.run_token)
      assert_equal "failed", batch.reload.state
      assert_equal "failed", execution.reload.state
      assert_match(/行3/, batch.message)
      assert_nil @shop.reload.gurunavi_url
    end
  end

  test "matching reads shops in batches rather than once per CSV row" do
    entries = 200.times.map { |i| entry("存在しないCSV#{i}", "大阪府大阪市中央区本町1-#{i + 1}-2", "https://r.gnavi.co.jp/perf#{i.to_s.rjust(6, '0')}/") }
    queries = []
    subscriber = ->(*args) { sql = args.last[:sql]; queries << sql if sql.match?(/\ASELECT.*FROM "shops"/m) }
    batch = nil
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { batch = batch_for(entries) }
    assert_equal 200, batch.rows.where(classification: "unmatched").count
    assert_operator queries.size, :<=, 4
  end
end
