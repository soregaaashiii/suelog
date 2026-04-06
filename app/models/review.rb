# /Users/kawamuratakuya/dev/suelog/app/models/review.rb
class Review < ApplicationRecord
belongs_to :shop
has_many :review_reports, dependent: :destroy

has_many_attached :food_photos
has_many_attached :exterior_photos
has_many_attached :interior_photos
has_many_attached :menu_photos

scope :approved, -> { where(approved: true) }
scope :pending, -> { where(approved: false) }

# ✅ 通報（pendingな通報が付いてるレビュー）
scope :reported, -> {
joins(:review_reports).merge(ReviewReport.pending).distinct
}

# ✅ 「評価」1本化（1〜5想定）
validates :rating,
presence: true,
numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 5 }

# ✅ 同一IP(ハッシュ)は同一店舗に1件だけ
validates :ip_hash, presence: true
validates :ip_hash, uniqueness: { scope: :shop_id }

validate :acceptable_review_photos

before_validation :ensure_edit_token

private

def ensure_edit_token
return if edit_token.present?

self.edit_token = SecureRandom.urlsafe_base64(24)
end

def acceptable_review_photos
attachment_groups = [
food_photos,
exterior_photos,
interior_photos,
menu_photos
]

attachment_groups.each do |group|
next unless group.attached?

group.each do |photo|
unless photo.content_type.in?(%w[image/jpeg image/png image/webp image/heic image/heif])
errors.add(:base, "画像は jpeg / png / webp / heic / heif のみアップロードできます")
end

if photo.blob.byte_size > 10.megabytes
errors.add(:base, "画像は1枚10MB以下にしてください")
end
end
end
end
end