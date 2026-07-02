# /Users/kawamuratakuya/dev/suelog/app/controllers/maps_controller.rb
# frozen_string_literal: true

class MapsController < ApplicationController
  def index
    @shops = Shop
      .approved
      .where.not(latitude: nil, longitude: nil)
      .order(
        Arel.sql("
          CASE WHEN last_confirmed_on IS NOT NULL THEN 0 ELSE 1 END ASC,
          last_confirmed_on DESC,
          created_at DESC
        ")
      )

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
        open_now: open_now_for(shop),
        open_now_label: open_now_for(shop) ? "営業中" : "営業時間外",
        lat: shop.latitude.to_f,
        lng: shop.longitude.to_f,
        url: shop_path(shop),
        phone_label: shop.phone.to_s,
        phone_url: phone_track_url_for(shop),
        map_url: map_track_url_for(shop),
        booking_label: booking_label_for(shop),
        booking_url: booking_track_url_for(shop)
      }
    end
  end

  private

  def phone_track_url_for(shop)
    digits = shop.phone.to_s.gsub(/[^0-9]/, "")
    return if digits.blank?

    track_click_shop_path(shop, kind: "phone_click", target_url: "tel:#{digits}")
  end

  def map_track_url_for(shop)
    query = [ shop.name, shop.address ].compact.join(" ")
    target_url =
      if shop.latitude.present? && shop.longitude.present?
        "https://www.google.com/maps/dir/?api=1&destination=#{ERB::Util.url_encode("#{shop.latitude},#{shop.longitude}")}"
      else
        "https://www.google.com/maps/search/?api=1&query=#{ERB::Util.url_encode(query)}"
      end

    track_click_shop_path(shop, kind: "map_click", target_url: target_url)
  end

  def booking_track_url_for(shop)
    target_url = booking_target_url_for(shop)
    return if target_url.blank?

    track_click_shop_path(shop, kind: "affiliate_click", target_url: target_url)
  end

  def booking_target_url_for(shop)
    custom_url = shop.try(:custom_affiliate_url).to_s.strip
    return custom_url if custom_url.present?

    hotpepper_url = shop.try(:hotpepper_url).to_s.strip
    return hotpepper_url if hotpepper_url.present?

    tabelog_affiliate_url = shop.try(:tabelog_affiliate_url).to_s.strip
    return tabelog_affiliate_url if tabelog_affiliate_url.present?

    tabelog_url = shop.try(:tabelog_url).to_s.strip
    return tabelog_url if tabelog_url.start_with?("http") && !tabelog_url.include?("not-found.local")

    nil
  end

  def booking_label_for(shop)
    return shop.custom_affiliate_label.to_s.strip.presence || "空席を確認" if shop.try(:custom_affiliate_url).present?
    return "ホットペッパーで見る" if shop.try(:hotpepper_url).present?
    return "食べログで見る" if shop.try(:tabelog_affiliate_url).present? || shop.try(:tabelog_url).to_s.start_with?("http")

    nil
  end

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

  def open_now_for(shop)
    return false unless shop.respond_to?(:open_now?)

    !!shop.open_now?
  rescue StandardError
    false
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
