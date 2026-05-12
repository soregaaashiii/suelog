# frozen_string_literal: true

require "csv"
require "uri"

def normalize_phone(phone)
  phone.to_s.gsub(/\D/, "")
end

def normalize_address(address)
  address.to_s
         .tr("０-９Ａ-Ｚａ-ｚ", "0-9A-Za-z")
         .gsub(/[[:space:]]/, "")
         .gsub("大阪府", "")
         .gsub("大阪市", "")
         .gsub("丁目", "-")
         .gsub("番地", "-")
         .gsub("番", "-")
         .gsub("号", "")
end

csv_path = Rails.root.join("tmp/tabelog_links.csv")

unless File.exist?(csv_path)
  puts "CSV not found: #{csv_path}"
  exit
end

matched = 0
skipped = 0

CSV.foreach(csv_path, headers: true) do |row|
  next if row["name"].blank?
  next if row["name"] == "name"

  tabelog_url = row["tabelog_url"].to_s.strip
  affiliate_url = row["affiliate_url"].to_s.strip

  unless tabelog_url.start_with?("http")
    puts "Skipped invalid tabelog_url: #{row['name']}"
    next
  end

  unless affiliate_url.blank? || affiliate_url.start_with?("http")
    puts "Skipped invalid affiliate_url: #{row['name']}"
    next
  end

  phone = normalize_phone(row["phone"])
  address = normalize_address(row["address"])

shop = Shop.find_by(
  "REPLACE(REPLACE(REPLACE(phone, '-', ''), ' ', ''), '　', '') = ?",
  phone
)

  if shop.nil?
    shop = Shop.all.find do |s|
      normalize_address(s.address) == address
    end
  end

  if shop.present?
    shop.update!(
      tabelog_url: tabelog_url,
      tabelog_affiliate_url: affiliate_url,
      tabelog_matched_at: Time.current,
      tabelog_match_method: phone.present? ? "phone" : "address"
    )

    matched += 1

    puts "Matched: #{shop.name}"
  else
    skipped += 1

    puts "Skipped: #{row['name']}"
  end
end

puts "----------------------"
puts "Matched: #{matched}"
puts "Skipped: #{skipped}"