# lib/tasks/shops.rake
namespace :shops do
desc "Backfill latitude/longitude for shops with missing coordinates"
task geocode_backfill: :environment do
scope = Shop.where(latitude: nil).or(Shop.where(longitude: nil))

total = scope.count
puts "[shops:geocode_backfill] target=#{total}"

ok = 0
ng = 0

scope.find_each.with_index(1) do |s, i|
addr = s.respond_to?(:geocode_address) ? s.geocode_address.to_s : s.address.to_s
addr = addr.to_s.strip

if addr.empty?
puts " - skip id=#{s.id} (blank address)"
next
end

begin
# geocoder gem の ActiveRecord 拡張
s.geocode

if s.latitude.present? && s.longitude.present?
s.save!(validate: false)
ok += 1
puts " ✓ (#{i}/#{total}) id=#{s.id} lat=#{s.latitude} lng=#{s.longitude} addr=#{addr}"
else
ng += 1
puts " ✗ (#{i}/#{total}) id=#{s.id} geocode returned nil addr=#{addr}"
end
rescue => e
ng += 1
puts " ! (#{i}/#{total}) id=#{s.id} ERROR #{e.class}: #{e.message}"
ensure
# Google側のレート制限回避（様子見で調整）
sleep 0.2
end
end

puts "[shops:geocode_backfill] done ok=#{ok} ng=#{ng}"
end
end
