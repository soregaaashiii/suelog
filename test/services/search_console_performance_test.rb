require "test_helper"
require_relative "../support/search_console_test_helpers"

class SearchConsolePerformanceTest < ActiveSupport::TestCase
  include SearchConsoleTestHelpers
  setup { seed_gsc_catalog }
  teardown { close_gsc_files }

  test "computes CTR and deltas from observed rows and never fills omitted pages with zero" do
    report = import_report
    rows = SearchConsolePerformance.new(report).apply(SeoPageCatalog.new.rows)
    row = rows.find { |r| r[:path] == "/areas/suita" }
    data = row[:performance]
    assert_equal BigDecimal("0.5"), data[:current][:ctr]
    assert_equal(-15, data[:deltas][:clicks])
    assert_equal(-500, data[:deltas][:impressions])
    assert_in_delta(-0.8333333, data[:deltas][:ctr].to_f, 0.00001)
    assert_equal BigDecimal("2"), data[:deltas][:position]
    assert_equal %w[low_ctr near_top click_decline].sort, data[:candidates].sort
    omitted = rows.find { |r| r[:path] == "/areas/toyonaka" }[:performance]
    assert_nil omitted[:current]
    assert_nil omitted[:deltas]
    assert_equal 10, omitted[:previous][:clicks]
    assert_empty omitted[:candidates]
    zero = rows.find { |r| r[:path] == "/stations/esaka" }[:performance]
    assert_equal 0, zero[:current][:clicks]
    assert_nil zero[:current][:ctr]
    assert_nil zero[:current][:position]
  end

  test "filters and sorts candidates without per row database queries" do
    report = import_report
    service = SearchConsolePerformance.new(report)
    catalog = SeoPageCatalog.new.rows
    queries = []
    callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] if payload[:sql].match?(/SELECT.*FROM ["`]?search_console_page_metrics/i) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      assert_equal ["/areas/suita"], service.apply(catalog, filter: "click_decline").map { |r| r[:path] }
      assert_equal ["/areas/suita"], service.apply(catalog, filter: "low_ctr").map { |r| r[:path] }
      assert_equal 3, service.apply(catalog, filter: "with_data").size
      assert_equal "/areas/suita", service.apply(catalog, sort: "click_change_asc").first[:path]
      assert_equal "/areas/suita/genre/izakaya", service.apply(catalog, sort: "position_asc").first[:path]
    end
    assert_equal 1, queries.length
  end

  test "noindex and 404 pages with historical impressions are review candidates not ranking claims" do
    report = SearchConsoleCsvImporter.new(current_file: gsc_upload(gsc_csv(["https://suelog.jp/areas/suita/smoking/heated-only", 2, 200, "1%", 15])), attributes: gsc_attributes).call
    rows = SearchConsolePerformance.new(report).apply(SeoPageCatalog.new.rows, filter: "publication_review")
    assert_equal 1, rows.length
    assert_equal "not_found", rows.first[:status]
    assert_equal ["publication_review"], rows.first[:performance][:candidates]
  end

  private

  def import_report
    current = gsc_csv(["https://suelog.jp/areas/suita", 5, 1000, "0.5%", 12],
      ["https://suelog.jp/areas/suita/genre/izakaya", 3, 100, "3%", 8], ["https://suelog.jp/stations/esaka", 0, 0, "0%", 0])
    previous = gsc_csv(["https://suelog.jp/areas/suita", 20, 1500, "1.33%", 10], ["https://suelog.jp/areas/toyonaka", 10, 200, "5%", 8])
    SearchConsoleCsvImporter.new(current_file: gsc_upload(current), previous_file: gsc_upload(previous), attributes: gsc_attributes(comparison: true)).call
  end
end
