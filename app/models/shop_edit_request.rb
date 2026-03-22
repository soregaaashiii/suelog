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

before_validation :normalize_proposed_opening_hours_json

private

def normalize_proposed_opening_hours_json
return unless respond_to?(:proposed_opening_hours_json=)

self.proposed_opening_hours_json = OpeningHoursParser.normalize_json(proposed_opening_hours_json)
end

def proposed_last_confirmed_on_not_future
return if proposed_last_confirmed_on.blank?

errors.add(:proposed_last_confirmed_on, "は未来の日付にできません") if proposed_last_confirmed_on > Date.current
end

def genre_other_required_when_other
return unless genre.to_s == "その他"
return if genre_other.to_s.strip.present?

# 既存店舗側も「その他」かつ genre_other 空なら、
# 今回は“変更していないだけ”なので編集依頼では弾かない
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