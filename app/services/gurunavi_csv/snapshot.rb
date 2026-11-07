require "digest"
module GurunaviCsv
  module Snapshot
    module_function
    FIELDS = %w[id name address gurunavi_url gurunavi_affiliate_url].freeze
    def call(shop)
      FIELDS.to_h { |key| [ key, shop.public_send(key) ] }.merge("updated_at" => shop.updated_at&.utc&.iso8601(6))
    end
    def matches?(shop, snapshot)
      snapshot.is_a?(Hash) && FIELDS.all? { |field| snapshot.key?(field) && shop.public_send(field) == snapshot[field] }
    end
    def version(shop) = Digest::SHA256.hexdigest(call(shop).to_json)
    def version_of(snapshot) = Digest::SHA256.hexdigest(snapshot.to_json)
    def url_values(shop) = { "gurunavi_url"=>shop.gurunavi_url, "gurunavi_affiliate_url"=>shop.gurunavi_affiliate_url }
  end
end
