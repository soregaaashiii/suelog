# frozen_string_literal: true

class ShopEditRequest < ApplicationRecord
belongs_to :shop

enum :status, { pending: 0, approved: 1, rejected: 2 }

has_many_attached :food_photos
has_many_attached :interior_photos
has_many_attached :exterior_photos
has_many_attached :menu_photos

THUMB_KINDS = %w[auto food exterior interior menu].freeze

enum :proposed_smoking_area, {
area_separated: 0,
area_all_smoking: 1,
area_unknown: 2
}, prefix: :proposed

enum :proposed_smoking_type, {
type_both_ok: 0,
type_electronic_only: 1,
type_paper_only: 2,
type_unknown: 3
}, prefix: :proposed

validates :proposed_smoking_area, presence: { message: "を選択してください（編集依頼では必須）" }
validates :proposed_smoking_type, presence: { message: "を選択してください（編集依頼では必須）" }

validate :proposed_last_confirmed_on_not_future
validate :genre_other_required_when_other
validate :proposed_thumbnail_values

before_validation :normalize_proposed_opening_hours_json
before_validation :normalize_proposed_smoking_values

private

def normalize_proposed_opening_hours_json
return unless respond_to?(:proposed_opening_hours_json=)

self.proposed_opening_hours_json = OpeningHoursParser.normalize_json(proposed_opening_hours_json)
end

def normalize_proposed_smoking_values
self.proposed_smoking_area =
case proposed_smoking_area.to_s
when "separated", "proposed_separated", "area_separated", "proposed_area_separated"
"area_separated"
when "all_smoking", "proposed_all_smoking", "area_all_smoking", "proposed_area_all_smoking"
"area_all_smoking"
when "unknown", "proposed_unknown", "area_unknown", "proposed_area_unknown"
"area_unknown"
else
proposed_smoking_area
end

self.proposed_smoking_type =
case proposed_smoking_type.to_s
when "both_ok", "proposed_both_ok", "type_both_ok", "proposed_type_both_ok"
"type_both_ok"
when "electronic_only", "proposed_electronic_only", "type_electronic_only", "proposed_type_electronic_only"
"type_electronic_only"
when "paper_only", "proposed_paper_only", "type_paper_only", "proposed_type_paper_only"
"type_paper_only"
when "unknown", "proposed_unknown", "type_unknown", "proposed_type_unknown"
"type_unknown"
else
proposed_smoking_type
end
end

def proposed_last_confirmed_on_not_future
return if proposed_last_confirmed_on.blank?

errors.add(:proposed_last_confirmed_on, "は未来の日付にできません") if proposed_last_confirmed_on > Date.current
end

def genre_other_required_when_other
return unless genre.to_s == "その他"
return if genre_other.to_s.strip.present?

if shop.present? &&
shop.genre.to_s == "その他" &&
shop.genre_other.to_s.strip.blank?
return
end

errors.add(:genre_other, "を入力してください（ジャンルが「その他」の場合）")
end

def proposed_thumbnail_values
if proposed_thumbnail_kind.present? && !THUMB_KINDS.include?(proposed_thumbnail_kind.to_s)
errors.add(:proposed_thumbnail_kind, "が不正です")
end

if proposed_thumbnail_index.present?
i = proposed_thumbnail_index.to_i
errors.add(:proposed_thumbnail_index, "は1以上で入力してください") if i < 1
end
end
end