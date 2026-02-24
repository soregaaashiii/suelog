
# frozen_string_literal: true

require "csv"

class ImportShopsFromCsv
DEFAULT_CSV_PATH = Rails.root.join("tmp", "shops_google.csv")

def self.call(csv_path: DEFAULT_CSV_PATH)
csv_path = Pathname(csv_path)

unless csv_path.exist?
Rails.logger.warn("CSV not found: #{csv_path}")
return { created: 0, updated: 0, skipped: 0, errors: 0 }
end

created = 0
updated = 0
skipped = 0
errors = 0

CSV.foreach(csv_path, headers: true).with_index(2) do |row, lineno|
begin
name = safe_strip(row["name"])
address = safe_strip(row["address"])
if name.blank? || address.blank?
skipped += 1
next
end

phone = safe_strip(row["phone"])
area = safe_strip(row["area"])
genre = safe_strip(row["genre"]) || "その他"
lat = safe_strip(row["latitude"])
lng = safe_strip(row["longitude"])
source = safe_strip(row["source"]) || "google"
place_id = safe_strip(row["place_id"])

opening_hours = safe_strip(row["opening_hours"])
nearest_station = safe_strip(row["nearest_station"])

raw_smoking = safe_strip(row["smoking_type"]) || safe_strip(row["smoking_area"]) || ""
smoking_type = map_smoking_type(raw_smoking)
smoking_area = map_smoking_area(raw_smoking)

missing = []
missing << "営業時間" if opening_hours.blank?
missing << "最寄駅" if nearest_station.blank?
missing << "喫煙エリア（席で喫煙可/喫煙所あり）" if smoking_area.blank?
missing << "喫煙タイプ（紙電子OK/電子のみ/紙のみ）" if smoking_type.blank?

note_lines = []
note_lines << "【自動取込】source=#{source}"
note_lines << "【自動取込】place_id=#{place_id}" if place_id.present?
note_lines << "【自動取込】raw_smoking=#{raw_smoking}" if raw_smoking.present?
note_lines << "【自動取込】不明: #{missing.join(' / ')}" if missing.any?

attrs = {
name: name,
address: address,
phone: phone,
area: area,
genre: genre,
latitude: lat,
longitude: lng,
opening_hours: opening_hours,
nearest_station: nearest_station,
smoking_type: smoking_type,
smoking_area: smoking_area,
last_confirmed_on: Date.current,
approved: missing.empty?, # 不明ゼロなら自動承認
rejected: false,
source: source,
place_id: place_id
}.compact

shop =
if place_id.present? && Shop.column_names.include?("place_id")
Shop.find_by(place_id: place_id)
elsif normalize_digits(phone).present?
Shop.find_by(normalized_phone: normalize_digits(phone))
else
Shop.find_by(name: name, address: address)
end

if shop
shop.assign_attributes(attrs)
else
shop = Shop.new(attrs)
end

# 必ず固定
shop.skip_photo_validation = true

merged = []
merged << shop.note.to_s.strip if shop.note.present?
merged.concat(note_lines)
shop.note = merged.reject(&:blank?).join("\n").presence

shop.save!
shop.previous_changes.key?("id") ? created += 1 : updated += 1

rescue => e
errors += 1
puts "[ERROR row=#{lineno}] #{row['name']} #{e.class}: #{e.message}"
end
end

puts "DONE"
puts "created=#{created} updated=#{updated} skipped=#{skipped} errors=#{errors}"

{ created: created, updated: updated, skipped: skipped, errors: errors }
end

def self.safe_strip(v)
s = v.to_s.strip
s.presence
end

def self.normalize_digits(phone)
phone.to_s.gsub(/[^0-9]/, "").presence
end

# 文字列から喫煙タイプを推測（両方含む場合は both_ok を優先）
def self.map_smoking_type(raw)
s = raw.to_s
has_paper = s.match?(/紙/)
has_ecig = s.match?(/電子|vape|iqos|アイコス/i)

return "both_ok" if has_paper && has_ecig
return "electronic_only" if has_ecig && !has_paper
return "paper_only" if has_paper && !has_ecig
nil
end

# Googleの検索結果だけでは「席で喫煙可 / 喫煙所あり」は基本分からないので、
# 確定できるワードがある時だけセットする（それ以外は nil）
def self.map_smoking_area(raw)
s = raw.to_s
return "all_smoking" if s.match?(/席で|全席|店内喫煙|喫煙可（席）/)
return "separated" if s.match?(/喫煙所/)
nil
end
end
