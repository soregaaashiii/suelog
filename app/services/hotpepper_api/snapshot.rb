require "digest"
module HotpepperApi
  module Snapshot
    module_function
    FIELDS = %w[id name address hotpepper_url hotpepper_affiliate_url].freeze
    def call(shop)
      FIELDS.to_h { |key| [ key, shop.public_send(key) ] }.merge("updated_at" => shop.updated_at&.utc&.iso8601(6))
    end
    def version(shop) = Digest::SHA256.hexdigest(call(shop).to_json)
    def version_of(snapshot) = Digest::SHA256.hexdigest(snapshot.to_json)
    def url_values(shop) = { "hotpepper_url"=>shop.hotpepper_url, "hotpepper_affiliate_url"=>shop.hotpepper_affiliate_url }
  end
end
