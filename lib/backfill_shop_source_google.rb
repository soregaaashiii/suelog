# frozen_string_literal: true

class BackfillShopSourceGoogle
def self.call
n = Shop.where(source: [nil, ""]).update_all(source: "google", updated_at: Time.current)
Rails.logger.info("DONE backfilled=#{n}")
n
end
end