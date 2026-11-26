# frozen_string_literal: true

class SearchConsolePerformance
  CANDIDATES = {
    "low_ctr" => "表示は多いがCTRが低い",
    "click_decline" => "クリック数が減少",
    "position_decline" => "掲載順位が低下",
    "near_top" => "11〜20位のページ",
    "publication_review" => "掲載設定を確認"
  }.freeze
  FILTERS = { "actionable" => "改善・確認候補すべて", "with_data" => "対象期間の実績あり", "no_data" => "対象期間のデータなし" }.merge(CANDIDATES).freeze
  SORTS = {
    "priority" => "改善の優先順", "position_change_desc" => "順位低下が大きい順",
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
        priority: priority(flags, current), deltas: current && previous ? differences(current, previous) : nil })
    end
    annotated.select! do |row|
      data = row[:performance]
      case filter
      when "actionable" then data[:candidates].any?
      when "with_data" then data[:current].present?
      when "no_data" then data[:current].nil?
      when *CANDIDATES.keys then data[:candidates].include?(filter)
      else true
      end
    end
    return annotated unless SORTS.key?(sort)

    annotated.sort_by do |row|
      data = row[:performance]
      if sort == "priority"
        click_change = data[:deltas]&.fetch(:clicks) || 0
        next [data[:priority][:rank], [click_change, 0].min, -(data[:current]&.fetch(:impressions) || 0), row[:path]]
      end
      value = case sort
      when "position_change_desc" then data[:deltas] && data[:deltas][:position] && -data[:deltas][:position]
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
    if @report&.comparison? && previous && current[:impressions] >= 100 && previous[:impressions] >= 100 && current[:position] && previous[:position] && current[:position] - previous[:position] >= 3
      flags << "position_decline"
    end
    flags
  end

  def priority(flags, current)
    rank, label, action = if flags.include?("publication_review")
      [1, "先に掲載確認", "掲載理由と実績期間を確認"]
    elsif (flags & %w[click_decline position_decline]).any?
      [1, "優先度 高", "減少した実績・検索条件・ページ内容を確認"]
    elsif flags.include?("low_ctr")
      [2, "優先度 中", "検索意図とタイトル・説明文を確認"]
    elsif flags.include?("near_top")
      [3, "優先度 通常", "内容と内部リンクを確認"]
    elsif current
      [4, "候補なし", nil]
    else
      [5, "データなし", nil]
    end
    { rank: rank, label: label, action: action }
  end

  def differences(current, previous)
    { clicks: current[:clicks] - previous[:clicks], impressions: current[:impressions] - previous[:impressions],
      ctr: current[:ctr] && previous[:ctr] ? current[:ctr] - previous[:ctr] : nil,
      position: current[:position] && previous[:position] ? current[:position] - previous[:position] : nil }
  end
end
