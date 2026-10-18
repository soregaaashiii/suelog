# /Users/kawamuratakuya/dev/suelog/app/controllers/maps_controller.rb
# frozen_string_literal: true

class MapsController < ApplicationController
  def index
    scope = Shop.approved.where.not(latitude: nil, longitude: nil)
    @shops = []
    unless request.format.json?
      @genres = Shop.selectable_genre_options
      @shops_count = scope.count
      @map_smoking_badges_payload = {}
      @map_shops_payload = []
      return
    end

    begin
      south, west, north, east = %i[south west north east].map { |key| Float(params.require(key)) }
      raise ArgumentError unless [south, west, north, east].all?(&:finite?) && south.between?(-90, 90) && north.between?(-90, 90) && west.between?(-180, 180) && east.between?(-180, 180) && south < north && west < east
    rescue ArgumentError, TypeError, ActionController::ParameterMissing
      return render json: { error: "検索範囲を確認してください" }, status: :unprocessable_entity
    end
    scope = scope.where(latitude: south..north, longitude: west..east)
    if params[:radius].present?
      begin
        center_lat, center_lng = %i[center_lat center_lng].map { |key| Float(params.require(key)) }
        radius = Float(params[:radius])
        raise ArgumentError unless center_lat.finite? && center_lng.finite? && center_lat.abs < 85 && center_lng.abs <= 180 && radius.between?(1, 800)
      rescue ArgumentError, TypeError, ActionController::ParameterMissing
        return render json: { error: "初期検索範囲を確認してください" }, status: :unprocessable_entity
      end
      ids = scope.pluck(:id, :latitude, :longitude).filter_map do |id, lat, lng|
        rad = Math::PI / 180
        a = Math.sin((lat - center_lat) * rad / 2)**2 + Math.cos(lat * rad) * Math.cos(center_lat * rad) * Math.sin((lng - center_lng) * rad / 2)**2
        id if 6_371_000 * 2 * Math.asin(Math.sqrt([a, 1].min)) <= radius
      end
      scope = scope.where(id: ids)
    end
    columns = Shop.column_names - %w[raw_import_text import_metadata public_store_details note]
    @shops = scope.select(*columns).order(last_confirmed_on: :desc, id: :desc).to_a
    @open_now_cache = {}
    keyword = params[:q].to_s.strip.downcase.unicode_normalize(:nfkc)
    station = params[:station].to_s.strip.downcase
    @shops.select! do |shop|
      target = [shop.name, shop.address, genre_label_for(shop), shop.nearest_station].join(" ").downcase.unicode_normalize(:nfkc)
      keyword.split.all? { |word| target.include?(word) } &&
        (station.blank? || shop.nearest_station.to_s.downcase.include?(station)) &&
        (params[:genre].blank? || genre_candidates_for(shop).include?(params[:genre]) || (params[:genre] == "その他" && shop.genre == "その他")) &&
        (params[:smoking_area].blank? || shop.smoking_area == params[:smoking_area]) &&
        (params[:smoking_type].blank? || shop.smoking_type == params[:smoking_type]) &&
        (params[:open_now_only] != "1" || open_now_for(shop))
    end
    total = @shops.size
    # Share identical icon markup instead of repeating it for every map record.
    @map_smoking_badges_payload = {}
    @map_shops_payload = @shops.map do |shop|
      badge_key = [ shop.smoking_area, shop.smoking_type ].join(":")
      @map_smoking_badges_payload[badge_key] ||= helpers.refine_smoking_badges(shop.smoking_area, shop.smoking_type).to_s
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
    render json: { shops: @map_shops_payload, badges: @map_smoking_badges_payload, clusters: [], total: total }
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

    @open_now_cache.fetch(shop.id) { @open_now_cache[shop.id] = !!shop.open_now? }
  rescue StandardError
    false
  end

  def genre_candidates_for(shop)
    values = []

    base_genre = shop.try(:genre).to_s.strip
    values << base_genre if base_genre.present? && base_genre != "その他"

    if base_genre == "その他"
      other = shop.try(:genre_other).to_s
      values.concat(Shop.split_genre_text(other))
    end

    if values.blank?
      label = genre_label_for(shop)
      values.concat(Shop.split_genre_text(label))
    end

    values
      .map { |v| v.to_s.strip }
      .reject(&:blank?)
      .uniq
  end
end
