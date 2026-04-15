class ShopClick < ApplicationRecord
  belongs_to :shop

  KINDS = %w[
    phone_click
    map_click
    affiliate_click
  ].freeze

  validates :kind, presence: true, inclusion: { in: KINDS }
end