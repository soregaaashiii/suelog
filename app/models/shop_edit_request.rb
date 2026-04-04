# /Users/kawamuratakuya/dev/suelog/app/models/shop_edit_request.rb
# frozen_string_literal: true

class ShopEditRequest < ApplicationRecord
belongs_to :shop

enum :status, { pending: 0, approved: 1, rejected: 2 }

has_many_attached :food_photos
has_many_attached :interior_photos
has_many_attached :exterior_photos
has_many_attached :menu_photos

THUMB_KINDS = %w[auto food exterior interior menu].freeze

# 既存DB/既存承認処理との互換性を維持するため、enumキー自体は area_* / type_* のまま維持
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

# --------------------------------------------------
# enum代入時点で ArgumentError が出ないように、setter で先に正規化する
# controller の build(...) や assign_attributes(...) でも効く
# --------------------------------------------------
def proposed_smoking_area=(value)
normalized = normalize_smoking_area_token(value)
super(normalized)
end

def proposed_smoking_type=(value)
normalized = normalize_smoking_type_token(value)
super(normalized)
end

private

def normalize_proposed_opening_hours_json
return unless respond_to?(:proposed_opening_hours_json=)

self.proposed_opening_hours_json =
if defined?(OpeningHoursParser)
OpeningHoursParser.normalize_json(proposed_opening_hours_json)
else
normalize_json_fallback(proposed_opening_hours_json)
end
end

def normalize_json_fallback(value)
case value
when nil
{}
when ActionController::Parameters
value.to_unsafe_h
when Hash
value
else
value.respond_to?(:to_h) ? value.to_h : {}
end
end

def normalize_proposed_smoking_values
# setter経由でもう正規化されるが、念のため再正規化して整合性を保つ
self[:proposed_smoking_area] = self.class.proposed_smoking_areas[normalize_smoking_area_token(proposed_smoking_area)] if normalize_smoking_area_token(proposed_smoking_area).present?
self[:proposed_smoking_type] = self.class.proposed_smoking_types[normalize_smoking_type_token(proposed_smoking_type)] if normalize_smoking_type_token(proposed_smoking_type).present?
end

def normalize_smoking_area_token(value)
raw = value.to_s.strip
return nil if raw.blank?

case raw
when "area_separated", "proposed_area_separated", "separated", "proposed_separated"
"area_separated"
when "area_all_smoking", "proposed_area_all_smoking", "all_smoking", "proposed_all_smoking"
"area_all_smoking"
when "area_unknown", "proposed_area_unknown", "unknown", "proposed_unknown"
"area_unknown"
else
self.class.proposed_smoking_areas.key?(raw) ? raw : nil
end
end

def normalize_smoking_type_token(value)
raw = value.to_s.strip
return nil if raw.blank?

case raw
when "type_both_ok", "proposed_type_both_ok", "both_ok", "proposed_both_ok"
"type_both_ok"
when "type_electronic_only", "proposed_type_electronic_only", "electronic_only", "proposed_electronic_only"
"type_electronic_only"
when "type_paper_only", "proposed_type_paper_only", "paper_only", "proposed_paper_only"
"type_paper_only"
when "type_unknown", "proposed_type_unknown", "unknown", "proposed_unknown"
"type_unknown"
else
self.class.proposed_smoking_types.key?(raw) ? raw : nil
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