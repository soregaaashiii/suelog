require "test_helper"
require_relative "../support/search_console_test_helpers"

class SearchConsoleCsvImporterTest < ActiveSupport::TestCase
  include SearchConsoleTestHelpers
  setup { seed_gsc_catalog }
  teardown { close_gsc_files }

  test "imports Japanese BOM and English CSV atomically and only persists exact catalog URLs" do
    current = "\uFEFF" + gsc_csv(["https://suelog.jp/areas/suita", 5, "1,000", "0.5%", 12],
      ["https://suelog.jp/shops/1", 3, 100, "3%", 3],
      ["https://suelog.jp/areas/suita?open_now_only=1", 2, 50, "4%", 5],
      ["https://example.com/areas/suita", 1, 10, "10%", 2], japanese: true)
    previous = gsc_csv(["https://suelog.jp/areas/suita", 20, 1500, "1.33%", 10])
    report = nil
    assert_difference({ "SearchConsoleImport.count" => 1, "SearchConsolePageMetric.count" => 2 }) do
      report = SearchConsoleCsvImporter.new(current_file: gsc_upload(current, filename: "ページ.csv"), previous_file: gsc_upload(previous), attributes: gsc_attributes(comparison: true)).call
    end
    assert report.comparison?
    assert_equal "ページ.csv", report.current_filename
    assert_equal({ "total" => 4, "matched" => 1, "unmatched" => 3 }, report.statistics.fetch("current"))
    metric = report.page_metrics.period_current.sole
    assert_equal 5, metric.clicks
    assert_equal 1000, metric.impressions
    assert_equal BigDecimal("12"), metric.position
    assert_equal "/areas/suita", metric.path
  end

  test "invalid comparison leaves no partial import or metric records" do
    current = gsc_csv(["https://suelog.jp/areas/suita", 5, 100, "5%", 8])
    malformed = "Query,Clicks,Impressions,CTR,Position\ncoffee,1,10,10%,1\n"
    assert_no_difference ["SearchConsoleImport.count", "SearchConsolePageMetric.count"] do
      error = assert_raises(SearchConsoleCsvImporter::InvalidCsv) do
        SearchConsoleCsvImporter.new(current_file: gsc_upload(current), previous_file: gsc_upload(malformed), attributes: gsc_attributes(comparison: true)).call
      end
      assert_match(/ページ別/, error.message)
    end
  end

  test "requires comparable dates and rejects future or inverted periods" do
    csv = gsc_csv(["https://suelog.jp/areas/suita", 1, 10, "10%", 5])
    [gsc_attributes(comparison: true).merge(previous_start: (Date.current - 55).iso8601),
      gsc_attributes(comparison: true).merge(previous_end: (Date.current - 1).iso8601),
      gsc_attributes.merge(period_end: (Date.current + 1).iso8601),
      gsc_attributes.merge(period_start: (Date.current - 1).iso8601, period_end: (Date.current - 2).iso8601)].each do |attributes|
      assert_raises(SearchConsoleCsvImporter::InvalidCsv) do
        SearchConsoleCsvImporter.new(current_file: gsc_upload(csv), previous_file: attributes[:previous_start] ? gsc_upload(csv) : nil, attributes: attributes).call
      end
    end
  end

  test "missing metadata returns Japanese field errors before saving" do
    csv = gsc_csv(["https://suelog.jp/areas/suita", 1, 10, "10%", 5])
    error = assert_raises(SearchConsoleCsvImporter::InvalidCsv) do
      SearchConsoleCsvImporter.new(current_file: gsc_upload(csv), attributes: { search_context: "x" * 501 }).call
    end
    assert_match(/対象期間の開始日/, error.message)
    assert_match(/検索条件メモ/, error.message)
    assert_match(/500文字/, error.message)
  end

  test "rejects duplicate URLs invalid metrics invalid encoding and oversized files" do
    row = ["https://suelog.jp/areas/suita", 1, 10, "10%", 5]
    invalid = [gsc_csv(row, row), gsc_csv(row, row.dup.tap { |r| r[0] = "https://suelog.jp:443/areas/suita" }),
      gsc_csv(row.dup.tap { |r| r[1] = 11 }), gsc_csv(row.dup.tap { |r| r[2] = "1,2" }),
      gsc_csv(row.dup.tap { |r| r[4] = "NaN" }), "\xFF".b, "x" * (SearchConsoleCsvImporter::MAX_BYTES + 1)]
    invalid.each do |csv|
      assert_no_difference "SearchConsoleImport.count" do
        assert_raises(SearchConsoleCsvImporter::InvalidCsv) { SearchConsoleCsvImporter.new(current_file: gsc_upload(csv), attributes: gsc_attributes).call }
      end
    end
  end

  test "zero impression rows retain observed zeros and an unknown position" do
    csv = gsc_csv(["https://suelog.jp/areas/suita", 0, 0, "0%", 0])
    report = SearchConsoleCsvImporter.new(current_file: gsc_upload(csv), attributes: gsc_attributes).call
    metric = report.page_metrics.sole
    assert_equal 0, metric.clicks
    assert_equal 0, metric.impressions
    assert_nil metric.position
  end

  test "rejects files with no matching URLs rather than replacing useful data" do
    csv = gsc_csv(["https://suelog.jp/shops/1", 1, 10, "10%", 5])
    error = assert_raises(SearchConsoleCsvImporter::InvalidCsv) do
      SearchConsoleCsvImporter.new(current_file: gsc_upload(csv), attributes: gsc_attributes).call
    end
    assert_match(/一致するURLがありません/, error.message)
  end
end
