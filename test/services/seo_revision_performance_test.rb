require "test_helper"

class SeoRevisionPerformanceTest < ActiveSupport::TestCase
  setup do
    @setting = SeoPageSetting.create!(path: "/areas/suita", title: "新タイトル")
    @revision = @setting.revisions.create!(created_at: 25.days.ago, before_values: {}, after_values: {})
    @report = SearchConsoleImport.new(period_start: Date.current - 17, period_end: Date.current - 4,
      previous_start: Date.current - 45, previous_end: Date.current - 32, previous_filename: "before.csv")
    @data = { previous: { clicks: 10, impressions: 100, ctr: 10, position: 8 },
      current: { clicks: 20, impressions: 400, ctr: 5, position: 6 },
      deltas: { clicks: 10, impressions: 300, ctr: -5, position: -2 } }
  end

  test "compares observed periods bracketing a single change and keeps CTR point differences" do
    result = compare
    assert result[:available]
    assert_equal 10, result[:deltas][:clicks]
    assert_equal(-5, result[:deltas][:ctr])
    assert_equal(-2, result[:deltas][:position])
    assert_equal 10, result[:previous][:clicks]
  end

  test "requires a comparison import and excludes the change day from both periods" do
    @report.previous_filename = nil
    assert_match(/比較期間付き/, compare[:reason])
    @report.previous_filename = "before.csv"
    @report.period_start = @revision.created_at.to_date
    assert_match(/変更当日/, compare[:reason])
    @report.period_start = Date.current - 17
    @report.previous_end = @revision.created_at.to_date
    assert_match(/変更当日/, compare[:reason])
  end

  test "does not attribute a period containing another change even outside the displayed history page" do
    other = @setting.revisions.create!(created_at: 10.days.ago, before_values: {}, after_values: {})
    assert_match(/別のSEO設定変更/, compare[:reason])
    other.update_columns(created_at: 50.days.ago)
    assert compare[:available]
    other.update_columns(created_at: @revision.created_at + 10.minutes)
    assert_match(/別のSEO設定変更/, compare[:reason])
  end

  test "does not substitute zero for missing rows and handles an empty history without queries" do
    @data[:previous] = nil
    assert_match(/両方のCSV/, compare[:reason])
    assert_equal({}, SeoRevisionPerformance.new(report: nil, setting: @setting, performance: nil).apply([]))
  end

  test "loads other changes once for a page of revisions" do
    revisions = [@revision] + Array.new(9) do |i|
      @setting.revisions.create!(created_at: (26 + i).days.ago, before_values: {}, after_values: {})
    end
    queries = []
    callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] if payload[:sql].match?(/SELECT.*FROM ["`]?seo_page_revisions/i) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      results = SeoRevisionPerformance.new(report: @report, setting: @setting, performance: @data).apply(revisions)
      assert_equal 10, results.size
      assert results.values.none? { |r| r[:available] }
    end
    assert_equal 1, queries.size
  end

  private

  def compare
    SeoRevisionPerformance.new(report: @report, setting: @setting, performance: @data).apply([@revision]).fetch(@revision.id)
  end
end
