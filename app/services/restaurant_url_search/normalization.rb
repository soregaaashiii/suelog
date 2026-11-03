require "uri"

module RestaurantUrlSearch
  module Normalization
    module_function

    def text(value)
      value.to_s.unicode_normalize(:nfkc).downcase.tr("‐‑‒–—―−", "-------").gsub(/[[:space:]\u3000]+/, " ").strip
    end

    def name(value)
      text(value).gsub(/[\s・･'"“”()\-]/, "")
    end

    def phone(value) = value.to_s.unicode_normalize(:nfkc).gsub(/\D/, "")

    def without_prefecture(value)
      text(value).sub(/\A(?:日本[、, ]*)?〒?\d{3}-?\d{4}\s*/, "").sub(/\A日本[、, ]*/, "")
        .sub(/\A(?:北海道|東京都|京都府|大阪府|.{2,3}県)/, "")
    end

    def municipality(value)
      without_prefecture(value).delete(" ")[/\A([^\d\s]+?市[^\d\s]*?区|[^\d\s]+?市市?|[^\d\s]+?区|[^\d\s]+?郡[^\d\s]+?[町村]|[^\d\s]+?[町村])/ , 1]
    end

    def address(value)
      without_prefecture(value).tr("ー", "-").gsub(/([一二三四五六七八九十]+)(?=丁目|番|号)/) do |number|
        digits = { "一"=>1, "二"=>2, "三"=>3, "四"=>4, "五"=>5, "六"=>6, "七"=>7, "八"=>8, "九"=>9 }
        parts = number.split("十", -1)
        parts.size == 2 ? ((parts[0].empty? ? 1 : digits[parts[0]].to_i) * 10 + digits[parts[1]].to_i).to_s : digits[number].to_s
      end.gsub(/丁目|番地?/, "-").gsub(/(?<=\d)号(?!館)/, "").gsub(/(\d)階/, '\1f').gsub(/\s/, "").sub(/-\z/, "")
    end

    def queries(shop, provider)
      queries = [{ stage: "name_city", query: [shop.name, municipality(shop.address), "site:#{provider.domain}"].compact.join(" ") }]
      digits = phone(shop.phone)
      if digits.length.between?(9, 11)
        formatted = if digits.length == 11
          digits.sub(/(\d{3})(\d{4})(\d{4})/, '\\1-\\2-\\3')
        elsif digits.length == 10 && digits.match?(/\A0[36]/)
          digits.sub(/(\d{2})(\d{4})(\d{4})/, '\\1-\\2-\\3')
        end
        variants = [text(shop.phone).gsub(/[^0-9-]/, ""), digits, formatted].compact
        variants.uniq.each { |number| queries << { stage: "phone", query: "#{number} site:#{provider.domain}" } }
      end
      queries
    end

    def google_url(query)
      "https://www.google.com/search?#{URI.encode_www_form(q: query)}"
    end
  end
end
