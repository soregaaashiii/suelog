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

def normalize_shop_name(name)
  name.to_s
      .tr("０-９Ａ-Ｚａ-ｚ", "0-9A-Za-z")
      .tr("＆×＋／～〜－ー―‐", "&x+/----")
      .gsub(/【旧店名】[^）)]*/, "")
      .gsub(/（旧店名[^）]*）/, "")
      .gsub(/\(旧店名[^)]*\)/, "")
      .gsub(/（[^）]*）/, "")
      .gsub(/\([^)]*\)/, "")
      .gsub(/[[:space:]]/, "")
      .gsub(/[・･.。、「」『』【】\[\]\/\\\-_,:：|｜]/, "")
      .gsub(/大阪梅田店\z/, "")
      .gsub(/梅田店\z/, "")
      .gsub(/大阪店\z/, "")
      .gsub(/本店\z/, "")
      .gsub(/店\z/, "")
      .downcase
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

  shop_name = row["name"].to_s.strip

  normalized_shop_name = normalize_shop_name(shop_name)

  matched_shops = Shop.where.not(name: [nil, ""]).select do |s|
    normalize_shop_name(s.name) == normalized_shop_name
  end

  if matched_shops.count > 1
    puts "Skipped duplicate name: #{shop_name}"
    skipped += 1
    next
  end

  shop = matched_shops.first

  if shop.present?
    shop.update!(
      tabelog_url: tabelog_url,
      tabelog_affiliate_url: affiliate_url,
      tabelog_matched_at: Time.current,
      tabelog_match_method: "name"
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