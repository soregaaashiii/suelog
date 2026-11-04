require "digest"

module GurunaviCsv
  module Normalizer
    module_function
    DASHES = "-‐‑‒–—―−ー".freeze
    NUMBER = /(?:[0-9]+|[一二三四五六七八九十]+)/
    def text(value) = value.to_s.unicode_normalize(:nfkc).downcase.strip
    def name(value) = text(value).gsub(/[[:space:]\u3000]+/, "")
    def clean_address(value)
      text(value).sub(/\A(?:日本[、,\s]*)?(?:〒\s*)?\d{3}[\-‐‑‒–—―−]?\d{4}\s*/, "").strip
    end
    def number(value)
      return value if value.match?(/\A\d+\z/)
      digits = { "一"=>1, "二"=>2, "三"=>3, "四"=>4, "五"=>5, "六"=>6, "七"=>7, "八"=>8, "九"=>9 }
      return digits[value].to_s if digits.key?(value)
      parts = value.split("十", -1)
      return value unless parts.size == 2 && (parts[0].empty? || digits.key?(parts[0])) && (parts[1].empty? || digits.key?(parts[1]))
      ((parts[0].empty? ? 1 : digits[parts[0]]) * 10 + digits.fetch(parts[1], 0)).to_s
    end
    def parts(value)
      value = clean_address(value)
      start = value.match(/\A(.*?)(#{NUMBER})(?:\s*)(丁目|番地|番|号|[#{Regexp.escape(DASHES)}])/)
      return [ name(value), "", false ] unless start
      prefix = name(start[1])
      rest = value[start[1].length..]
      numbers = []
      loop do
        token = rest.match(/\A\s*(#{NUMBER})\s*(丁目|番地|番|号|[#{Regexp.escape(DASHES)}])?/)
        break unless token
        numbers << number(token[1])
        rest = rest[token[0].length..]
        break if token[2].nil? || token[2] == "号"
      end
      [ prefix + numbers.join("-"), name(rest), numbers.present? ]
    end
    def address(value)
      street, building, = parts(value)
      # Separate the parcel from the building; do not rewrite digits or long vowels in the building.
      "#{street}|#{building}"
    end
    def identity(store_name, store_address)
      return nil if name(store_name).blank? || clean_address(store_address).blank?
      Digest::SHA256.hexdigest([ name(store_name), address(store_address) ].to_json)
    end
    def street(value) = parts(value).first
    def municipality(value) = RestaurantUrlSearch::Normalization.municipality(clean_address(value)).to_s
    def complete?(value) = municipality(value).present? && parts(value).last
    def grams(value)
      chars = name(value).chars.first(80)
      chars.each_cons(2).map(&:join).uniq
    end
    def similarity(a, b)
      return 1.0 if name(a) == name(b) && name(a).present?
      left, right = grams(a), grams(b)
      return 0.0 if left.empty? || right.empty?
      2.0 * (left & right).size / (left.size + right.size)
    end
  end
end
