class ShopReport < ApplicationRecord
  belongs_to :shop

  enum :status, { pending: 0, resolved: 1, rejected: 2 }
end
