# /Users/kawamuratakuya/Desktop/吸えログデータ/dev/suelog/lib/approve_imported_shops.rb
approved = 0
kept_pending = 0

scope = Shop.where(rejected: [false, nil])

scope.find_each do |shop|
  missing = []
  missing << "営業時間" if shop.opening_hours.blank?
  missing << "最寄駅" if shop.nearest_station.blank?
  missing << "喫煙エリア" if shop.smoking_area.blank?
  missing << "喫煙タイプ" if shop.smoking_type.blank?

  unknown_in_note = shop.note.to_s.include?("【自動取込】不明:")

  if missing.any? || unknown_in_note
    shop.update!(approved: false, rejected: false)
    kept_pending += 1
    next
  end

  shop.update!(approved: true, rejected: false)
  approved += 1
end

puts "DONE approved=#{approved} kept_pending=#{kept_pending}"