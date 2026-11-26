# frozen_string_literal: true

class SeoPageWorklist
  def initialize(report)
    @report = report
  end

  def apply(rows, status: nil, comparison: nil)
    paths = rows.map { |row| row.fetch(:path) }
    tasks = SeoPageTask.where(path: paths).pluck(:path, :status, :handled_on, :updated_at).to_h do |path, state, date, updated|
      [path, { status: state, handled_on: date, updated_at: updated }]
    end
    ready = ready_paths(rows)
    rows.filter_map do |row|
      task = tasks.fetch(row[:path], { status: "pending", handled_on: nil, updated_at: nil })
      available = ready.include?(row[:path])
      next if SeoPageTask::STATUSES.key?(status) && task[:status] != status
      next if comparison == "ready" && !available
      next if comparison == "not_ready" && available
      row.merge(task: task, comparison_ready: available)
    end
  end

  private

  def ready_paths(rows)
    return [] unless @report&.comparison?
    paths = rows.select { |r| r.dig(:performance, :current) && r.dig(:performance, :previous) }.map { |r| r[:path] }
    return [] if paths.empty?
    revisions = SeoPageRevision.joins(:seo_page_setting).where(seo_page_settings: { path: paths })
    latest_ids = SeoPageRevision.select("MAX(id)").group(:seo_page_setting_id)
    latest = revisions.where(id: latest_ids).pluck("seo_page_settings.path", "seo_page_revisions.created_at")
    range = @report.previous_start.in_time_zone.beginning_of_day..@report.period_end.in_time_zone.end_of_day
    counts = revisions.where(created_at: range).group("seo_page_settings.path").count
    latest.filter_map do |path, timestamp|
      day = timestamp.in_time_zone.to_date
      path if @report.previous_end < day && @report.period_start > day && counts[path] == 1
    end
  end
end
