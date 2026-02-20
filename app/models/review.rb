class Review < ApplicationRecord
belongs_to :shop
has_many :review_reports, dependent: :destroy

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

before_validation :ensure_edit_token

private

def ensure_edit_token
return if self.edit_token.present?
self.edit_token = SecureRandom.urlsafe_base64(24)
end
end