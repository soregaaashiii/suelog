


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

# 入力例:
# 月 11:00-14:00,17:00-23:00
# 火 休み
#
# 出力（UIと合わせた1日1枠+休憩）
# {
# "monday"=>{"closed"=>false,"open"=>"11:00","close"=>"23:00","break_enabled"=>true,"break_start"=>"14:00","break_end"=>"17:00"},
# "tuesday"=>{"closed"=>true}
# }
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
# 2枠目までを「中休み」に落とし込む（それ以上は無視）
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

# 最低限 open/close が無い日は保存しない（未設定扱い）
next if open.blank? || close.blank?

break_enabled = truthy?(v["break_enabled"])
break_start = presence(v["break_start"])
break_end = presence(v["break_end"])

out[day] = {
"closed" => false,
"open" => open,
"close" => close,
"break_enabled" => break_enabled && break_start.present? && break_end.present?,
"break_start" => break_start,
"break_end" => break_end
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

