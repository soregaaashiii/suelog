# frozen_string_literal: true

class SearchConsoleImport < ApplicationRecord
  has_many :page_metrics, class_name: "SearchConsolePageMetric", dependent: :delete_all
  validates :period_start, :period_end, :current_filename, :search_context, presence: true
  validates :search_context, length: { maximum: 500 }
  validate :valid_periods

  def comparison? = previous_filename.present?
  def period_label = "#{period_start}〜#{period_end}"

  def previous_label
    comparison? ? "#{previous_start}〜#{previous_end}" : nil
  end

  private

  def valid_periods
    if period_start && period_end
      errors.add(:base, "対象期間の終了日は開始日以降にしてください。") if period_end < period_start
      errors.add(:base, "対象期間の終了日は今日以前にしてください。") if period_end > Date.current
    end
    return unless comparison?
    unless previous_start && previous_end && period_start && period_end
      errors.add(:base, "比較CSVを取り込む場合は、両期間の開始日・終了日が必要です。")
      return
    end
    if previous_end < previous_start || previous_end >= period_start
      errors.add(:base, "比較期間は対象期間より前の、重ならない期間にしてください。")
    end
    if (period_end - period_start) != (previous_end - previous_start)
      errors.add(:base, "対象期間と比較期間の日数をそろえてください。")
    end
  end
end
