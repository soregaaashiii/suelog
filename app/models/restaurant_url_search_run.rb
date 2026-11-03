require "digest"

class RestaurantUrlSearchRun < ApplicationRecord
  belongs_to :shop
  serialize :payload, coder: JSON
  validates :provider, inclusion: { in: RestaurantUrlSearch::Provider::CONFIG.keys }

  def self.input_digest(shop, provider)
    Digest::SHA256.hexdigest([shop.name, shop.address, shop.phone, shop.public_send("#{provider}_url"), shop.public_send("#{provider}_affiliate_url")].to_json)
  end
end
