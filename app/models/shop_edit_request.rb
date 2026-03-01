# frozen_string_literal: true

class ShopEditRequest < ApplicationRecord
belongs_to :shop

enum :status, { pending: 0, approved: 1, rejected: 2 }

# 添付（編集依頼に紐づく）
has_many_attached :food_photos
has_many_attached :interior_photos
has_many_attached :exterior_photos
has_many_attached :menu_photos

THUMB_KINDS = %w[auto food exterior interior menu].freeze

# proposed_smoking_*（DB: integer）
enum :proposed_smoking_area, {
separated: 0,
all_smoking: 1
}, prefix: true

enum :proposed_smoking_type, {
both_ok: 0,
electronic_only: 1,
paper_only: 2
}, prefix: true

validates :proposed_smoking_area, presence: { message: "を選択してください（編集依頼では必須）" }
validates :proposed_smoking_type, presence: { message: "を選択してください（編集依頼では必須）" }

validate :proposed_last_confirmed_on_not_future
validate :genre_other_required_when_other
validate :proposed_thumbnail_values
validate :at_least_one_photo_attached

# 🔥 構造化営業時間を整形して保存
before_validation :normalize_proposed_opening_hours_json

private

def normalize_proposed_opening_hours_json
self.proposed_opening_hours_json = OpeningHoursParser.normalize_json(proposed_opening_hours_json)
end

def proposed_last_confirmed_on_not_future
return if proposed_last_confirmed_on.blank?
errors.add(:proposed_last_confirmed_on, "は未来の日付にできません") if proposed_last_confirmed_on > Date.current
end

def genre_other_required_when_other
return if genre.blank?
return unless genre.to_s == "その他"
errors.add(:genre_other, "を入力してください（ジャンルが「その他」の場合）") if genre_other.to_s.strip.blank?
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

def at_least_one_photo_attached
any =
(food_photos.attached? rescue false) ||
(interior_photos.attached? rescue false) ||
(exterior_photos.attached? rescue false) ||
(menu_photos.attached? rescue false)

errors.add(:base, "写真を1枚以上添付してください（料理/内観/外観/メニューどれでもOK）") unless any
end
end