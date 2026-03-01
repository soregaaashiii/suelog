# frozen_string_literal: true

class OpeningHoursParser
DAYS = {
"日" => "sunday",
"月" => "monday",
"火" => "tuesday",
"水" => "wednesday",
"木" => "thursday",
"金" => "friday",
"土" => "saturday"
}.freeze

# 旧テキスト → json（CSV等の互換用）
def self.parse_legacy_text(text)
return {} if text.blank?

out = {}

text.to_s.lines.each do |line|
s = line.strip
next if s.blank?

m = s.match(/\A([日月火水木金土])\s+(.*)\z/)
next unless m

day_ja = m[1]
rest = m[2].to_s.strip
day = DAYS[day_ja]
next unless day

if rest.match?(/休|定休日|closed/i)
out[day] = { "closed" => true }
next
end

periods = []
rest.split(/[、,\/]/).each do |part|
p = part.strip
next if p.blank?

t = p.match(/(\d{1,2}):(\d{2})\s*[-–—〜~]\s*(\d{1,2}):(\d{2})/)
next unless t

o = format("%02d:%02d", t[1].to_i, t[2].to_i)
c = format("%02d:%02d", t[3].to_i, t[4].to_i)
periods << [o, c]
end

next if periods.empty?

if periods.size == 1
out[day] = {
"closed" => false,
"open" => periods[0][0],
"close" => periods[0][1],
"break_enabled" => false
}
else
first_open, first_close = periods[0]
second_open, second_close = periods[1]
out[day] = {
"closed" => false,
"open" => first_open,
"close" => second_close,
"break_enabled" => true,
"break_start" => first_close,
"break_end" => second_open
}
end
end

out
end

# フォームから来たopening_hours_jsonを整形（空文字を消す）
# - closed が true の日は {closed:true} に固定
# - open/close が両方ない日は「未設定扱い」で保存しない
# - break_enabled は break_start/end が揃った時だけ true
def self.normalize_json(input)
h = (input || {}).to_h
out = {}

h.each do |day, v|
v = (v || {}).to_h

closed = truthy?(v["closed"])
if closed
out[day] = { "closed" => true }
next
end

open = presence(v["open"])
close = presence(v["close"])
next if open.blank? || close.blank?

break_start = presence(v["break_start"])
break_end = presence(v["break_end"])
break_enabled = truthy?(v["break_enabled"]) && break_start.present? && break_end.present?

out[day] = {
"closed" => false,
"open" => open,
"close" => close,
"break_enabled" => break_enabled,
"break_start" => (break_enabled ? break_start : nil),
"break_end" => (break_enabled ? break_end : nil)
}.compact
end

out
end

def self.truthy?(v)
v == true || v.to_s == "1" || v.to_s.downcase == "true" || v.to_s == "on"
end

def self.presence(v)
s = v.is_a?(String) ? v : v.to_s
s = s.strip
s.presence
end
end