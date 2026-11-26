require "test_helper"
require_relative "../support/search_console_test_helpers"

class SeoPageWorklistTest < ActiveSupport::TestCase
  include SearchConsoleTestHelpers
  setup { seed_gsc_catalog }
  teardown { close_gsc_files }

  test "task edits persist independently of metadata and reject stale or invalid changes" do
    editor = ->(attrs, version = "new") { SeoPageTaskEditor.new(path: "/areas/suita", attributes: attrs, expected_version: version).call }
    assert_no_difference ["SeoPageTask.count", "SeoPageRevision.count", "SeoPageSetting.count"] do
      assert_not editor.call({ status: "pending", note: "", handled_on: "" })
    end
    assert editor.call({ status: "observing", note: " 経過を確認 ", handled_on: "" })
    task = SeoPageTask.find_by!(path: "/areas/suita")
    assert_equal Date.current, task.handled_on
    assert_equal "経過を確認", task.note
    assert_raises(SeoPageTaskEditor::Conflict) { editor.call({ status: "completed" }) }
    version = task.version_token
    assert_raises(ActiveRecord::RecordInvalid) { editor.call({ status: "unknown" }, version) }
    assert_raises(ActiveRecord::RecordInvalid) { editor.call({ status: "completed", handled_on: "bad date" }, version) }
    assert_raises(ActiveRecord::RecordInvalid) { editor.call({ handled_on: (Date.current + 1).iso8601 }, version) }
    assert_raises(ActiveRecord::RecordInvalid) { editor.call({ note: "a" * 2001 }, version) }
    assert_equal "observing", task.reload.status
    assert_equal version, task.version_token
    assert_no_difference ["SeoPageRevision.count", "SeoPageSetting.count"] do
      assert editor.call({ status: "completed", note: "対応済み" }, version)
    end
    assert_equal Date.current, task.reload.handled_on
    timestamp = task.updated_at
    assert_not editor.call({ status: "completed", note: "対応済み" }, task.version_token)
    assert_equal timestamp, task.reload.updated_at
  end

  test "task filters treat unrecorded paths as pending and survive new imports" do
    SeoPageTask.create!(path: "/areas/suita", status: "skipped", note: "後で判断", handled_on: Date.current)
    2.times do
      report = import_comparison
      rows = SearchConsolePerformance.new(report).apply(SeoPageCatalog.new.rows)
      service = SeoPageWorklist.new(report)
      assert_equal ["/areas/suita"], service.apply(rows, status: "skipped").map { |r| r[:path] }
      assert service.apply(rows, status: "pending").none? { |r| r[:path] == "/areas/suita" }
    end
    assert_equal "後で判断", SeoPageTask.find_by!(path: "/areas/suita").note
  end

  test "ready filter agrees with revision comparison and excludes mixed changes or missing data" do
    report = import_comparison
    setting = SeoPageSetting.create!(path: "/areas/suita", title: "新しいタイトル")
    revision = setting.revisions.create!(created_at: 25.days.ago, before_values: {}, after_values: {})
    rows = SearchConsolePerformance.new(report).apply(SeoPageCatalog.new.rows)
    service = SeoPageWorklist.new(report)
    ready = service.apply(rows, comparison: "ready")
    assert_equal ["/areas/suita"], ready.map { |r| r[:path] }
    assert_equal "pending", ready.first[:task][:status]
    assert SeoRevisionPerformance.new(report: report, setting: setting, performance: ready.first[:performance]).apply([revision])[revision.id][:available]
    assert service.apply(rows, comparison: "not_ready").none? { |r| r[:path] == "/areas/suita" }
    setting.revisions.create!(created_at: 10.days.ago, before_values: {}, after_values: {})
    assert_empty service.apply(rows, comparison: "ready")
    assert_empty SeoPageWorklist.new(nil).apply(rows, comparison: "ready")
  end

  test "readiness needs both CSV rows and excludes an earlier edit within the comparison span" do
    report = import_comparison
    setting = SeoPageSetting.create!(path: "/areas/suita", title: "タイトル")
    older = setting.revisions.create!(created_at: 40.days.ago, before_values: {}, after_values: {})
    setting.revisions.create!(created_at: 25.days.ago, before_values: {}, after_values: {})
    rows = SearchConsolePerformance.new(report).apply(SeoPageCatalog.new.rows)
    assert_empty SeoPageWorklist.new(report).apply(rows, comparison: "ready")
    older.update_columns(created_at: 50.days.ago)
    assert_equal 1, SeoPageWorklist.new(report).apply(rows, comparison: "ready").size
    report.page_metrics.where(period: "previous").delete_all
    rows = SearchConsolePerformance.new(report).apply(SeoPageCatalog.new.rows)
    assert_empty SeoPageWorklist.new(report).apply(rows, comparison: "ready")
  end

  test "batch loads task and revision state without per page queries" do
    report = import_comparison
    rows = SearchConsolePerformance.new(report).apply(SeoPageCatalog.new.rows)
    queries = []
    callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] if payload[:sql].match?(/SELECT.*FROM ["`]?seo_page_(tasks|revisions)/i) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      assert_equal rows.size, SeoPageWorklist.new(report).apply(rows).size
    end
    assert_equal 3, queries.size
  end

  private

  def import_comparison
    SearchConsoleCsvImporter.new(current_file: gsc_upload(gsc_csv(["https://suelog.jp/areas/suita", 5, 1000, "0.5%", 12])),
      previous_file: gsc_upload(gsc_csv(["https://suelog.jp/areas/suita", 20, 1500, "1.33%", 9])),
      attributes: { period_start: Date.current - 17, period_end: Date.current - 4, previous_start: Date.current - 45,
        previous_end: Date.current - 32, search_context: "ウェブ・全デバイス" }).call
  end
end
