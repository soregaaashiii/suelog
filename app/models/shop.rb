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
# 営業時間（昼休憩対応）
# opening_hours例:
# 月 11:00-14:00,17:00-23:00
# 火 休み
# =========================

# 今日の営業時間帯（配列）を返す: [[open_min, close_min], ...] or nil（休み） or []（未設定）
def today_time_ranges
schedule = parse_opening_hours_by_day(opening_hours)
return [] if schedule.empty?
key = wday_ja(Time.zone.today.wday)
schedule[key]
end

# 現在営業中（昼休憩も考慮）
def open_now?
ranges = today_time_ranges
return false if ranges.blank?
return false if ranges.nil?

now = Time.zone.now
now_min = now.hour * 60 + now.min

ranges.any? do |open_min, close_min|
if close_min > open_min
now_min >= open_min && now_min < close_min
else
# 例: 20:00-02:00（跨ぎ）
now_min >= open_min || now_min < close_min
end
end
end

# 表示用： [["月","11:00-14:00 / 17:00-23:00"], ["火","休み"], ...]
def opening_hours_lines
schedule = parse_opening_hours_by_day(opening_hours)
order = %w[月 火 水 木 金 土 日]

return order.map { |d| [d, "未設定"] } if schedule.empty?

order.map do |d|
ranges = schedule[d]
if ranges.nil?
[d, "休み"]
elsif ranges.blank?
[d, "未設定"]
else
text = ranges.map { |a, b| "#{minutes_to_hhmm(a)}-#{minutes_to_hhmm(b)}" }.join(" / ")
[d, text]
end
end
end

AREAS = [
"阿倍野","阿倍野橋","旭区清水","朝潮橋","淡路","石橋阪大前","泉大津","泉ヶ丘","泉佐野","和泉中央",
"今里","茨木","茨木市","梅田","江坂","難波","大阪阿部野橋","大阪上本町","大阪狭山市","大阪天満宮",
"大日","大東市","大正","岡町","貝塚","香里園","柏原","門真市","岸和田","京橋","喜連瓜破","九条",
"河内小阪","河内国分","河内長野","河内松原","岸辺","北新地","北千里","北花田","布施","堺","堺東",
"桜川","新金岡","新今宮","新大阪","心斎橋","住道","千里中央","千林大宮","高槻","高槻市","玉造",
"天下茶屋","天王寺","天満橋","豊中","中百舌鳥","長居","西梅田","西九条","野田","東岸和田","東三国",
"東梅田","東大阪市","東花園","枚方市","平野","深井","藤井寺","古市","弁天町","本町","松原","箕面",
"都島","守口市","八尾","山田","淀屋橋","四ツ橋"
].freeze

private

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

def wday_ja(wday)
%w[日 月 火 水 木 金 土][wday]
end

# 戻り値:
# - schedule[day] = nil -> 休み
# - schedule[day] = [[open,close],[open,close]...] -> 複数帯（昼休憩対応）
def parse_opening_hours_by_day(text)
return {} if text.blank?

h = {}
text.to_s.lines.each do |line|
s = line.strip
next if s.blank?

m = s.match(/\A([月火水木金土日])\s+(.*)\z/)
next unless m

day = m[1]
rest = m[2].strip

if rest.match?(/休|定休日|closed/i)
h[day] = nil
next
end

ranges = []
rest.split(/[、,\/]/).each do |part|
p = part.strip
next if p.blank?

t = p.match(/(\d{1,2}):(\d{2})\s*[-–—〜~]\s*(\d{1,2}):(\d{2})/)
next unless t

open_min = t[1].to_i * 60 + t[2].to_i
close_min = t[3].to_i * 60 + t[4].to_i
ranges << [open_min, close_min]
end

h[day] = ranges if ranges.any?
end

h
end

def minutes_to_hhmm(min)
hh = (min / 60) % 24
mm = min % 60
format("%02d:%02d", hh, mm)
end

def set_normalized_phone
digits = phone.to_s.gsub(/[^0-9]/, "")
self.normalized_phone = digits.presence
end
end