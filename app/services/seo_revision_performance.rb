# frozen_string_literal: true

# Compare only observed CSV periods wholly on either side of a single change.
class SeoRevisionPerformance
  def initialize(report:, setting:, performance:)
    @report, @setting, @performance = report, setting, performance
  end

  def apply(revisions)
    return {} if revisions.empty?
    changes = if @report&.comparison?
      range = @report.previous_start.in_time_zone.beginning_of_day..@report.period_end.in_time_zone.end_of_day
      @setting.revisions.where(created_at: range).pluck(:id, :created_at)
    else
      []
    end
    revisions.to_h do |revision|
      [revision.id, comparison(revision, changes)]
    end
  end

  private

  def comparison(revision, changes)
    return unavailable("比較期間付きの検索実績CSVを取り込んで選択してください。") unless @report&.comparison?
    day = revision.created_at.in_time_zone.to_date
    unless @report.previous_end < day && @report.period_start > day
      return unavailable("変更当日を除き、変更前に終了する比較期間と変更翌日以降に始まる対象期間を選んでください。")
    end
    mixed = changes.any? do |id, timestamp|
      date = timestamp.in_time_zone.to_date
      id != revision.id && date >= @report.previous_start && date <= @report.period_end
    end
    return unavailable("比較範囲に別のSEO設定変更があるため、この変更単独では比較できません。") if mixed
    unless @performance && @performance[:current] && @performance[:previous]
      return unavailable("このページが両方のCSVに含まれていません。欠落データは0として扱いません。")
    end
    { available: true, current: @performance[:current], previous: @performance[:previous], deltas: @performance[:deltas] }
  end

  def unavailable(reason) = { available: false, reason: reason }
end
