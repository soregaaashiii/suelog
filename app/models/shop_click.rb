class ShopClick < ApplicationRecord
  belongs_to :shop
  belongs_to :article, optional: true

  KINDS = %w[
    phone_click
    map_click
    affiliate_click
    article_shop_click
  ].freeze

  validates :kind, presence: true, inclusion: { in: KINDS }
end