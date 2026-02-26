# app/models/shop_edit_request.rb
class ShopEditRequest < ApplicationRecord
belongs_to :shop

enum :status, { pending: 0, approved: 1, rejected: 2 }

# ✅ 編集依頼に写真を添付できるようにする（ActiveStorage）
has_many_attached :food_photos
has_many_attached :interior_photos
has_many_attached :exterior_photos
has_many_attached :menu_photos

THUMB_KINDS = %w[auto food exterior interior menu].freeze

# ✅ proposed_smoking_* は shops と同じ enum に合わせる（DBは integer）
enum :proposed_smoking_area, {
separated: 0, # 喫煙所あり
all_smoking: 1 # 席で喫煙可
}, prefix: true

enum :proposed_smoking_type, {
both_ok: 0, # 紙・加熱式OK
electronic_only: 1, # 加熱式のみ
paper_only: 2 # 紙のみ
}, prefix: true

# ✅ 編集依頼では喫煙ステータス必須
validates :proposed_smoking_area, presence: { message: "を選択してください（編集依頼では必須）" }
validates :proposed_smoking_type, presence: { message: "を選択してください（編集依頼では必須）" }


validate :proposed_last_confirmed_on_not_future
validate :genre_other_required_when_other
validate :proposed_thumbnail_values
before_validation :sync_proposed_opening_hours_data


def proposed_opening_hours_data_for_form
  source = proposed_opening_hours_data.presence || Shop.opening_hours_data_from_text(proposed_opening_hours)
  Shop.normalize_opening_hours_data(source)
end

private

def sync_proposed_opening_hours_data
  source = proposed_opening_hours_data.presence || Shop.opening_hours_data_from_text(proposed_opening_hours)
  normalized = Shop.normalize_opening_hours_data(source)
  self.proposed_opening_hours_data = normalized
  self.proposed_opening_hours = Shop.build_opening_hours_text(normalized)
end

private

def proposed_last_confirmed_on_not_future
return if proposed_last_confirmed_on.blank?
errors.add(:proposed_last_confirmed_on, "は未来の日付にできません") if proposed_last_confirmed_on > Date.current
end

# ✅ genre が空（＝変更しない）はOK / genre が「その他」のときだけ genre_other 必須
def genre_other_required_when_other
return if genre.blank?
return unless genre.to_s == "その他"
errors.add(:genre_other, "を入力してください（ジャンルが「その他」の場合）") if genre_other.to_s.strip.blank?
end

# ✅ サムネ候補のバリデーション（空＝変更しない でOK）
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