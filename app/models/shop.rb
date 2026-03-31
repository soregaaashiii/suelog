# /Users/kawamuratakuya/Desktop/吸えログデータ/dev/suelog/app/models/shop.rb
# frozen_string_literal: true

class Shop < ApplicationRecord
# ===== Associations =====
has_many :reviews, dependent: :destroy
has_many :shop_edit_requests, dependent: :destroy
has_many :shop_reports, dependent: :destroy

# ===== ActiveStorage =====
has_many_attached :food_photos
has_many_attached :interior_photos
has_many_attached :exterior_photos
has_many_attached :menu_photos

# ===== Smoking status =====
enum :smoking_area, {
separated: 0, # 喫煙所あり
all_smoking: 1, # 席で喫煙可
unknown: 2 # 不明
}, prefix: true

enum :smoking_type, {
both_ok: 0, # 紙・加熱式OK
electronic_only: 1, # 加熱式のみ
paper_only: 2, # 紙のみ
unknown: 3 # 不明
}, prefix: true

# ===== Scopes =====
scope :approved, -> { where(approved: true) }

scope :keyword, lambda { |q|
kw = q.to_s.strip
next all if kw.blank?

like = "%#{kw}%"
where(
<<~SQL.squish,
shops.name LIKE :like
OR shops.address LIKE :like
OR shops.area LIKE :like
OR shops.nearest_station LIKE :like
OR shops.phone LIKE :like
OR shops.note LIKE :like
OR shops.genre LIKE :like
OR shops.genre_other LIKE :like
OR shops.opening_hours_text LIKE :like
OR shops.holiday_hours_text LIKE :like
OR shops.closed_days_text LIKE :like
SQL
like: like
)
}

scope :text_like, lambda { |column, value|
v = value.to_s.strip
next all if v.blank?

like = "%#{sanitize_sql_like(v)}%"
where("shops.#{column} LIKE ?", like)
}

scope :genre_like, lambda { |value|
v = value.to_s.strip
next all if v.blank?

like = "%#{sanitize_sql_like(v)}%"
where("shops.genre LIKE ? OR shops.genre_other LIKE ?", like, like)
}

# ===== Validations =====
validates :name, :address, :last_confirmed_on, presence: { message: "を入力してください" }
validates :genre, presence: { message: "を選択してください" }

validates :smoking_area, presence: { message: "を選択してください" }, if: :approved?
validates :smoking_type, presence: { message: "を選択してください" }, if: :approved?

validates :tabelog_url,
format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "は正しいURLを入力してください" },
allow_blank: true

validates :hotpepper_url,
format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "は正しいURLを入力してください" },
allow_blank: true

validate :last_confirmed_on_cannot_be_future

# 電話番号の重複防止（digitsのみ）
before_validation :set_normalized_phone
validates :normalized_phone, uniqueness: true, allow_nil: true, allow_blank: true

# opening_hours_json は既存データ互換のため残す
before_validation :normalize_opening_hours_json

# ===== Geocoding =====
def geocode_address
[address, area]
.compact
.map(&:to_s)
.map { |v| v.gsub(/\s+/, " ").strip }
.reject(&:blank?)
.join(" ")
end

geocoded_by :geocode_address, latitude: :latitude, longitude: :longitude
after_validation :safe_geocode, if: :should_geocode?

def safe_geocode
geocode
rescue Geocoder::Error => e
Rails.logger.warn("[geocode skipped] #{e.class}: #{e.message}")
self.latitude = nil if latitude_changed?
self.longitude = nil if longitude_changed?
true
end

def ensure_geocoded!
return false if geocode_address.blank?
return false unless geocoding_enabled?

geocode

if latitude.present? && longitude.present?
save!(validate: false)
true
else
false
end
rescue Geocoder::Error => e
Rails.logger.warn("[ensure_geocoded!] #{e.class}: #{e.message}")
false
end

# ===== Display helpers =====
def display_genre
return "" if genre.blank?

genre == "その他" ? genre_other.to_s : genre.to_s
end

def smoking_area_label
case smoking_area
when "all_smoking"
"席で喫煙可"
when "separated"
"喫煙所あり"
when "unknown"
"不明"
else
"未設定"
end
end

def smoking_type_label
case smoking_type
when "both_ok"
"紙・加熱式どちらもOK"
when "electronic_only"
"加熱式タバコのみOK"
when "paper_only"
"紙タバコのみOK"
when "unknown"
"不明"
else
"未設定"
end
end

# =========================
# サムネイル（安全版）
# =========================
def thumbnail_attachment
kind = (respond_to?(:thumbnail_kind) ? thumbnail_kind.to_s : "").presence || "auto"
idx = (respond_to?(:thumbnail_index) ? thumbnail_index.to_i : 1)
idx = 1 if idx <= 0

attachments =
case kind
when "food"
safe_attachments(food_photos)
when "interior"
safe_attachments(interior_photos)
when "exterior"
safe_attachments(exterior_photos)
when "menu"
safe_attachments(menu_photos)
else
auto_thumbnail_attachments
end

pick_attachment_from(attachments, idx)
rescue StandardError => e
Rails.logger.warn("[thumbnail_attachment] #{e.class}: #{e.message}")
nil
end

# =========================
# 営業時間（簡易テキスト表示）
# =========================
def display_opening_hours_text
opening_hours_text.presence || derived_opening_hours_text.presence || "未設定"
end

def display_holiday_hours_text
holiday_hours_text.presence || "未設定"
end

def display_closed_days_text
closed_days_text.presence || derived_closed_days_text.presence || "未設定"
end

# =========================
# 既存の構造化JSON互換
# =========================
def opening_hours_data
(opening_hours_json.presence || {}).to_h
end

def open_now?
today = opening_hours_data[today_key]
return false if today.blank?
return false if truthy?(today["closed"])

now = Time.zone.now
now_min = now.hour * 60 + now.min

open_min = hhmm_to_min(today["open"])
close_min = hhmm_to_min(today["close"])
return false if open_min.nil? || close_min.nil?

if truthy?(today["break_enabled"])
bs = hhmm_to_min(today["break_start"])
be = hhmm_to_min(today["break_end"])
return false if bs && be && within_range?(now_min, bs, be)
end

within_range?(now_min, open_min, close_min)
end

def opening_hours_lines
order = [
["月", "monday"],
["火", "tuesday"],
["水", "wednesday"],
["木", "thursday"],
["金", "friday"],
["土", "saturday"],
["日", "sunday"]
]

data = opening_hours_data

order.map do |label, key|
d = data[key]

if d.blank?
[label, "未設定"]
elsif truthy?(d["closed"])
[label, "休み"]
else
base = "#{d["open"]}-#{d["close"]}"
if truthy?(d["break_enabled"]) && d["break_start"].present? && d["break_end"].present?
[label, "#{base}（休憩 #{d["break_start"]}-#{d["break_end"]}）"]
else
[label, base]
end
end
end
end

AREAS = [
"阿倍野", "阿倍野橋", "旭区清水", "朝潮橋", "淡路", "石橋阪大前", "泉大津", "泉ヶ丘", "泉佐野", "和泉中央",
"今里", "茨木", "茨木市", "梅田", "江坂", "難波", "大阪阿部野橋", "大阪上本町", "大阪狭山市", "大阪天満宮",
"大日", "大東市", "大正", "岡町", "貝塚", "香里園", "柏原", "門真市", "岸和田", "京橋", "喜連瓜破", "九条",
"河内小阪", "河内国分", "河内長野", "河内松原", "岸辺", "北新地", "北千里", "北花田", "布施", "堺", "堺東",
"桜川", "新金岡", "新今宮", "新大阪", "心斎橋", "住道", "千里中央", "千林大宮", "高槻", "高槻市", "玉造",
"天下茶屋", "天王寺", "天満橋", "豊中", "中百舌鳥", "長居", "西梅田", "西九条", "野田", "東岸和田", "東三国",
"東梅田", "東大阪市", "東花園", "枚方市", "平野", "深井", "藤井寺", "古市", "弁天町", "本町", "松原", "箕面",
"都島", "守口市", "八尾", "山田", "淀屋橋", "四ツ橋"
].freeze

private

def normalize_opening_hours_json
return unless respond_to?(:opening_hours_json)

self.opening_hours_json = OpeningHoursParser.normalize_json(opening_hours_json)
end

def derived_opening_hours_text
rows = opening_hours_lines.reject { |_label, value| value == "未設定" || value == "休み" }
return nil if rows.blank?

rows.map { |label, value| "#{label} #{value}" }.join(" / ")
end

def derived_closed_days_text
rows = opening_hours_lines.select { |_label, value| value == "休み" }
return nil if rows.blank?

rows.map(&:first).join("・")
end

def today_key
%w[sunday monday tuesday wednesday thursday friday saturday][Time.zone.today.wday]
end

def hhmm_to_min(hhmm)
return nil if hhmm.blank?

m = hhmm.to_s.match(/\A(\d{1,2}):(\d{2})\z/)
return nil unless m

m[1].to_i * 60 + m[2].to_i
end

def within_range?(now_min, start_min, end_min)
if end_min > start_min
now_min >= start_min && now_min < end_min
else
now_min >= start_min || now_min < end_min
end
end

def truthy?(value)
value == true || value.to_s == "1"
end

def geocoding_enabled?
lookup = (Geocoder.config.lookup rescue nil).to_s
if lookup.include?("google")
key = ENV["GOOGLE_MAPS_API_KEY"].to_s.strip
key = ENV["GMAPS_API_KEY"].to_s.strip if key.blank?
return key.present?
end
true
end

def should_geocode?
return false unless geocoding_enabled?
return false if geocode_address.blank?

address_changed = will_save_change_to_address?
area_changed = will_save_change_to_area?
missing_latlng = latitude.blank? || longitude.blank?

address_changed || area_changed || missing_latlng
end

def last_confirmed_on_cannot_be_future
return if last_confirmed_on.blank?

errors.add(:last_confirmed_on, "は未来の日付にできません") if last_confirmed_on > Date.current
end

def set_normalized_phone
digits = phone.to_s.gsub(/[^0-9]/, "")
self.normalized_phone = digits.presence
end

def safe_attachments(collection)
return [] unless collection.respond_to?(:attachments)

collection.attachments.select do |att|
begin
att.present? && att.blob.present? && att.blob.key.present?
rescue StandardError
false
end
end
end

def auto_thumbnail_attachments
[
safe_attachments(food_photos),
safe_attachments(exterior_photos),
safe_attachments(interior_photos),
safe_attachments(menu_photos)
].flatten
end

def pick_attachment_from(attachments, idx)
return nil if attachments.blank?

picked = attachments[idx - 1] || attachments.first
return nil unless picked.present?

begin
picked.blob
picked
rescue StandardError
nil
end
end
end