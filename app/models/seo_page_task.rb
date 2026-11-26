# frozen_string_literal: true

class SeoPageTask < ApplicationRecord
  STATUSES = { "pending" => "未対応", "in_progress" => "対応中", "observing" => "経過観察", "completed" => "対応済み", "skipped" => "見送り" }.freeze
  attr_readonly :path
  before_validation { self.note = note.to_s.strip.presence }
  validates :path, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES.keys }
  validates :note, length: { maximum: 2000 }
  validate do
    errors.add(:path, "はSEOページ一覧のURLを指定してください") unless GeographicPageMetadata.definition(path)
    errors.add(:handled_on, "は今日以前の日付にしてください") if handled_on && handled_on > Date.current
    errors.add(:handled_on, "は正しい日付を入力してください") if handled_on_before_type_cast.present? && handled_on.nil?
  end

  def version_token = persisted? ? lock_version.to_s : "new"
end
