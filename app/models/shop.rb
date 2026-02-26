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
all_smoking: 1 # 席で喫煙可
}

enum :smoking_type, {
both_ok: 0, # 紙・加熱式OK
electronic_only: 1, # 加熱式のみ
paper_only: 2 # 紙のみ
}

# ===== Scopes =====
scope :approved, -> { where(approved: true) }

scope :keyword, ->(q) do
kw = q.to_s.strip
next all if kw.blank?

like = "%#{kw}%"
where(
<<~SQL.squish, like: like
shops.name LIKE :like
OR shops.address LIKE :like
OR shops.area LIKE :like
OR shops.nearest_station LIKE :like
OR shops.phone LIKE :like
OR shops.note LIKE :like
OR shops.genre LIKE :like
OR shops.genre_other LIKE :like
OR shops.opening_hours LIKE :like
SQL
)
end

# ===== Validations =====
validates :name, :address, :last_confirmed_on, presence: { message: "を入力してください" }
validates :genre, presence: { message: "を選択してください" }
validates :smoking_area, presence: { message: "を選択してください" }
validates :smoking_type, presence: { message: "を選択してください" }

validate :last_confirmed_on_cannot_be_future

# 電話番号の重複防止（digitsのみ）
before_validation :set_normalized_phone
validates :normalized_phone, uniqueness: true, allow_nil: true, allow_blank: true

# opening_hours_json を整形して保存
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
self.latitude = nil if self.latitude_changed?
self.longitude = nil if self.longitude_changed?
true
end

# ===== Display helpers =====
def display_genre
return "" if genre.blank?

genre == "その他" ? genre_other.to_s : genre.to_s
end

# =========================
# 営業時間（構造化JSON + フォールバック）
# =========================

# 優先: opening_hours_json（構造化）
# 無ければ: opening_hours（文字列）をパース
def opening_hours_data
data = (opening_hours_json || {}).to_h
return data if data.present?

OpeningHoursParser.parse_legacy_text(opening_hours)
end

def open_now?
today = opening_hours_data[today_key]
return false if today.blank?
return false if today["closed"]

now = Time.zone.now
now_min = now.hour * 60 + now.min

open_min = hhmm_to_min(today["open"])
close_min = hhmm_to_min(today["close"])
return false if open_min.nil? || close_min.nil?

# 中休み
if today["break_enabled"]
bs = hhmm_to_min(today["break_start"])
be = hhmm_to_min(today["break_end"])
if bs && be && within_range?(now_min, bs, be)
return false
end
end

within_range?(now_min, open_min, close_min)
end

# 表示用： [["月","11:00-23:00（休憩 14:00-17:00）"], ...]
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
elsif d["closed"]
[label, "休み"]
else
base = "#{d["open"]}-#{d["close"]}"
if d["break_enabled"] && d["break_start"].present? && d["break_end"].present?
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
self.opening_hours_json = OpeningHoursParser.normalize_json(opening_hours_json)
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
# 跨ぎ（例 20:00-02:00）
now_min >= start_min || now_min < end_min
end
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
end