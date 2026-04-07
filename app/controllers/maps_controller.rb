# /Users/kawamuratakuya/Desktop/吸えログデータ/dev/suelog/app/controllers/maps_controller.rb
# frozen_string_literal: true

class MapsController < ApplicationController
def index
@shops = Shop
.approved
.where.not(latitude: nil, longitude: nil)
.order(created_at: :desc)

@shops_count = @shops.size

@genres = @shops
.flat_map { |shop| genre_candidates_for(shop) }
.map(&:strip)
.reject(&:blank?)
.uniq
.sort

@map_shops_payload = @shops.map do |shop|
{
id: shop.id,
name: shop.name.to_s,
address: shop.address.to_s,
nearest_station: shop.nearest_station.to_s,
genre: shop.try(:genre).to_s,
genre_label: genre_label_for(shop),
genre_tokens: genre_candidates_for(shop),
smoking_area: shop.try(:smoking_area).to_s,
smoking_area_label: smoking_area_label_for(shop),
smoking_type: shop.try(:smoking_type).to_s,
smoking_type_label: smoking_type_label_for(shop),
lat: shop.latitude.to_f,
lng: shop.longitude.to_f,
url: shop_path(shop)
}
end
end

private

def genre_label_for(shop)
if shop.respond_to?(:display_genre)
shop.display_genre.to_s
elsif shop.respond_to?(:genre)
shop.genre.to_s
else
""
end
end

def smoking_area_label_for(shop)
if shop.respond_to?(:smoking_area_i18n)
shop.smoking_area_i18n.to_s
elsif shop.respond_to?(:smoking_area_label)
shop.smoking_area_label.to_s
else
""
end
end

def smoking_type_label_for(shop)
if shop.respond_to?(:smoking_type_i18n)
shop.smoking_type_i18n.to_s
elsif shop.respond_to?(:smoking_type_label)
shop.smoking_type_label.to_s
else
""
end
end

def genre_candidates_for(shop)
values = []

base_genre = shop.try(:genre).to_s.strip
values << base_genre if base_genre.present? && base_genre != "その他"

if base_genre == "その他"
other = shop.try(:genre_other).to_s
values.concat(split_genre_text(other))
end

if values.blank?
label = genre_label_for(shop)
values.concat(split_genre_text(label))
end

values
.map { |v| v.to_s.strip }
.reject(&:blank?)
.uniq
end

def split_genre_text(text)
text.to_s
.split(/[、,\/／｜|・]+/)
.map(&:strip)
.reject(&:blank?)
end
end