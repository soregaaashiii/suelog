# frozen_string_literal: true

class SearchConsolePerformance
  CANDIDATES = {
    "low_ctr" => "表示は多いがCTRが低い",
    "click_decline" => "クリック数が減少",
    "near_top" => "11〜20位のページ",
    "publication_review" => "掲載設定を確認"
  }.freeze
  FILTERS = { "with_data" => "対象期間の実績あり", "no_data" => "対象期間のデータなし" }.merge(CANDIDATES).freeze
  SORTS = {
    "clicks_desc" => "クリック数が多い順", "impressions_desc" => "表示回数が多い順",
    "ctr_asc" => "CTRが低い順", "position_asc" => "掲載順位が高い順", "click_change_asc" => "クリック減少が大きい順"
  }.freeze

  def initialize(report)
    @report = report
  end

  def apply(rows, filter: nil, sort: nil)
    annotated = rows.map do |row|
      current = metrics.dig(row[:path], "current")
      previous = metrics.dig(row[:path], "previous")
      flags = candidates(row, current, previous)
      row.merge(performance: { current: current, previous: previous, candidates: flags,
        deltas: current && previous ? differences(current, previous) : nil })
    end
    annotated.select! do |row|
      data = row[:performance]
      case filter
      when "with_data" then data[:current].present?
      when "no_data" then data[:current].nil?
      when *CANDIDATES.keys then data[:candidates].include?(filter)
      else true
      end
    end
    return annotated unless SORTS.key?(sort)

    annotated.sort_by do |row|
      data = row[:performance]
      value = case sort
      when "clicks_desc" then data[:current] && -data[:current][:clicks]
      when "impressions_desc" then data[:current] && -data[:current][:impressions]
      when "ctr_asc" then data[:current] && data[:current][:ctr]
      when "position_asc" then data[:current] && data[:current][:position]
      when "click_change_asc" then data[:deltas] && data[:deltas][:clicks]
      end
      [value.nil? ? 1 : 0, value || 0, row[:path]]
    end
  end

  private

  def metrics
    @metrics ||= begin
      result = {}
      if @report
        @report.page_metrics.pluck(:path, :period, :clicks, :impressions, :position).each do |path, period, clicks, impressions, position|
          (result[path] ||= {})[period] = { clicks: clicks, impressions: impressions,
            ctr: impressions.positive? ? BigDecimal(clicks.to_s) * 100 / impressions : nil,
            position: position }
        end
      end
      result
    end
  end

  def candidates(row, current, previous)
    return [] unless current
    return current[:impressions].positive? ? ["publication_review"] : [] unless row[:status] == "index"
    flags = []
    flags << "low_ctr" if current[:impressions] >= 100 && current[:ctr] && current[:ctr] < 1 && current[:position] && current[:position] <= 20
    flags << "near_top" if current[:impressions] >= 100 && current[:position] && current[:position] > 10 && current[:position] <= 20
    if @report&.comparison? && previous && previous[:clicks] >= 10 && current[:clicks] * 10 <= previous[:clicks] * 7
      flags << "click_decline"
    end
    flags
  end

  def differences(current, previous)
    { clicks: current[:clicks] - previous[:clicks], impressions: current[:impressions] - previous[:impressions],
      ctr: current[:ctr] && previous[:ctr] ? current[:ctr] - previous[:ctr] : nil,
      position: current[:position] && previous[:position] ? current[:position] - previous[:position] : nil }
  end
end
