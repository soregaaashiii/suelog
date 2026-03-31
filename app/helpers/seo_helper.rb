# /Users/kawamuratakuya/dev/suelog/app/helpers/seo_helper.rb
module SeoHelper
def full_area_label_from_params(params)
area = params[:area].presence
station = params[:station].presence

return station if station.present?
return area if area.present?

nil
end

def home_title(params)
area_label = full_area_label_from_params(params)

if area_label.present?
"吸えログ｜#{area_label}で喫煙できる飲食店検索"
else
"吸えログ｜大阪で喫煙できる飲食店検索（梅田・難波・天王寺）"
end
end

def home_description(params)
area_label = full_area_label_from_params(params)

if area_label.present?
"#{area_label}で喫煙できる飲食店を探せる吸えログ。席で喫煙可・喫煙所あり・加熱式のみ対応の店を検索できます。"
else
"大阪で喫煙できる飲食店を探せる吸えログ。梅田・難波・天王寺を中心に、席で喫煙可・喫煙所あり・加熱式のみ対応の店を検索できます。"
end
end

def shop_title(shop)
area_or_station = shop.nearest_station.presence || shop.area.presence || "大阪"
"#{shop.name}｜#{area_or_station}で喫煙できる飲食店｜吸えログ"
end

def shop_description(shop)
parts = []
parts << "#{shop.name}の喫煙情報"
parts << shop.area if shop.area.present?
parts << shop.nearest_station if shop.nearest_station.present?
parts << shop.display_genre if shop.respond_to?(:display_genre) && shop.display_genre.present?

smoking_label =
if shop.all_smoking?
"席で喫煙可"
elsif shop.separated?
"喫煙所あり"
end

parts << smoking_label if smoking_label.present?

"#{parts.join('｜')}。営業時間・住所・最寄駅などを掲載。"
end
end