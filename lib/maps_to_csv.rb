# frozen_string_literal: true
require "httparty"
require "csv"

API_KEY = ENV["GOOGLE_MAPS_API_KEY"].to_s.strip
abort "GOOGLE_MAPS_API_KEY が空です" if API_KEY.empty?

TEXTSEARCH_URL = "https://maps.googleapis.com/maps/api/place/textsearch/json"
DETAILS_URL    = "https://maps.googleapis.com/maps/api/place/details/json"

# Google types をざっくり日本語ジャンルへ寄せる（必要なら後で増やす）
TYPE_TO_GENRE = {
  "izakaya" => "居酒屋",
  "bar" => "バー",
  "cafe" => "カフェ",
  "restaurant" => "レストラン",
  "night_club" => "ナイトクラブ",
  "meal_takeaway" => "テイクアウト",
  "bakery" => "ベーカリー"
}.freeze

def guess_genre(types)
  types ||= []
  types.each do |t|
    g = TYPE_TO_GENRE[t]
    return g if g
  end
  # fallback
  "飲食店"
end

def text_search(query)
  res = HTTParty.get(TEXTSEARCH_URL, query: { query:, key: API_KEY, language: "ja" })
  json = JSON.parse(res.body)
  raise "TextSearch error: #{json["status"]} #{json["error_message"]}" unless json["status"] == "OK" || json["status"] == "ZERO_RESULTS"
  json
end

def place_details(place_id)
  fields = "name,formatted_phone_number,international_phone_number,formatted_address,types,geometry"
  res = HTTParty.get(DETAILS_URL, query: { place_id:, fields:, key: API_KEY, language: "ja" })
  json = JSON.parse(res.body)
  raise "Details error: #{json["status"]} #{json["error_message"]}" unless json["status"] == "OK"
  json["result"]
end

def normalize_phone(phone)
  return "" if phone.nil?
  phone.to_s.gsub(/[^\d+]/, "")
end

areas = [
  "梅田",
  "難波",
  "心斎橋",
  "天王寺",
  "京橋",
  "新大阪",
  "鶴橋",
  "本町",
  "淀屋橋",
  "新今宮"
]

keywords = [
  "喫煙可",
  "喫煙可能",
  "店内喫煙"
]

out_path = "/Users/kawamuratakuya/Desktop/吸えログデータ/dev/suelog/tmp/shops_google.csv"
Dir.mkdir(File.dirname(out_path)) unless Dir.exist?(File.dirname(out_path))

CSV.open(out_path, "w", write_headers: true, headers: %w[name phone address genre area latitude longitude smoking_type source place_id]) do |csv|
  seen = {} # place_id重複排除

  areas.each do |area|
    keywords.each do |kw|
      query = "#{area} #{kw}"
      puts "==> Searching: #{query}"

      ts = text_search(query)
      results = ts["results"] || []

      results.each do |r|
        place_id = r["place_id"]
        next if place_id.nil? || seen[place_id]
        seen[place_id] = true

        # Details で電話番号等を取得
        begin
          d = place_details(place_id)
        rescue => e
          warn "Details failed place_id=#{place_id}: #{e}"
          next
        end

        name = d["name"] || r["name"] || ""
        address = d["formatted_address"] || r["formatted_address"] || ""
        phone = normalize_phone(d["formatted_phone_number"] || d["international_phone_number"])
        types = d["types"] || r["types"] || []
        genre = guess_genre(types)

        loc = (d.dig("geometry", "location") || r.dig("geometry", "location") || {})
        lat = loc["lat"]
        lng = loc["lng"]

        csv << [name, phone, address, genre, area, lat, lng, kw, "google", place_id]
      end
    end
  end
end

puts "DONE -> #{out_path}"
