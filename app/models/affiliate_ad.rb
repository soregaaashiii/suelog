# /Users/kawamuratakuya/dev/suelog/app/models/affiliate_ad.rb
class AffiliateAd < ApplicationRecord
  # ActiveStorage（画像アップロード）
  has_one_attached :image

  # バリデーション
  validates :key, presence: true, uniqueness: true
  validates :url, presence: true

  # スコープ
  scope :active, -> { where(active: true) }

  # 表示用の画像URLを取得
  def display_image_path
    if image.attached?
      Rails.application.routes.url_helpers.url_for(image)
    elsif image_path.present?
      image_path
    else
      nil
    end
  end
end