# lib/backfill_shop_source_google.rb
n = Shop.where(source: [nil, ""]).update_all(source: "google", updated_at: Time.current)
puts "DONE backfilled=#{n}"

