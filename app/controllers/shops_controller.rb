# /Users/kawamuratakuya/dev/suelog/app/controllers/shops_controller.rb
# frozen_string_literal: true

class ShopsController < ApplicationController
  require "digest"
  require "set"

  helper_method :contribution_count, :current_contribution_badge

  TRACKABLE_CLICK_KINDS = %w[
    phone_click
    map_click
    affiliate_click
  ].freeze

  RECOMMENDATION_IMAGE_PRELOADS = {
    food_photos_attachments: :blob,
    interior_photos_attachments: :blob,
    exterior_photos_attachments: :blob,
    menu_photos_attachments: :blob
  }.freeze

  RECOMMENDATION_RANKING_COLUMNS = %w[
    shops.id
    shops.opening_hours_json
    shops.holiday_hours_text
    shops.opening_hours_text
    shops.last_confirmed_on
    shops.created_at
  ].join(", ").freeze

  RecommendationRankedShop = Struct.new(:id, keyword_init: true)

  def index
    redirect_to root_path, status: :moved_permanently
  end

  def map
    scope = Shop.approved.where.not(latitude: nil, longitude: nil)

    if params[:lat].present? && params[:lng].present?
      lat = params[:lat].to_f
      lng = params[:lng].to_f
      scope = scope.near([lat, lng], 0.5, units: :km)
    end

    @shops = scope.order(
      Arel.sql("
        CASE WHEN last_confirmed_on IS NOT NULL THEN 0 ELSE 1 END ASC,
        last_confirmed_on DESC,
        created_at DESC
      ")
    )
  end

  def show
    @shop = Shop.find(params[:id])

    track_page_view(shop: @shop)

    @review = Review.new
    @approved_reviews = @shop.reviews.approved.order(created_at: :desc)

    ip_hash = ip_hash_for_request
    @my_review = @shop.reviews.find_by(ip_hash: ip_hash)

    @nearby_shops = nearby_shops_for(@shop)
    @same_genre_shops = same_genre_shops_for(@shop)
    @popular_shops = popular_shops_for(@shop)
    @related_articles = related_articles_for(@shop)
  end

  def new
    @shop = Shop.new
  end

  def possible_duplicates
    @phone = params[:phone].to_s
    normalized = normalize_phone(@phone)

    @shops =
      if normalized.present?
        Shop.where(normalized_phone: normalized).order(created_at: :desc)
      else
        Shop.none
      end
  end

  def create
    @shop = Shop.new(shop_params)
    @shop.approved = false

    normalized = normalize_phone(@shop.phone)

    if normalized.present?
      existing = Shop.where(normalized_phone: normalized).order(created_at: :desc)
      if existing.exists?
        @possible_duplicates = existing.limit(20)
        @dup_phone_for_link = @shop.phone.to_s
        flash.now[:alert] = "同じ電話番号の店舗が既に登録されている可能性があります。重複の疑いを確認してください。"
        return render :new, status: :unprocessable_entity
      end
    end

    if @shop.save
      increment_contribution!
      msg, achieved_badge_name = contribution_message_and_badge

      flash[:contribution_count] = contribution_count
      flash[:badge_achieved] = achieved_badge_name if achieved_badge_name.present?

      redirect_to shop_path(@shop), notice: msg
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @shop = Shop.find(params[:id])
  end

  def update
    @shop = Shop.find(params[:id])

    if @shop.update(shop_params)
      redirect_to shop_path(@shop), notice: "更新しました"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @shop = Shop.find(params[:id])
    @shop.destroy
    redirect_to root_path
  end

  def track_click
    @shop = Shop.find(params[:id])

    kind = params[:kind].to_s
    target_url = params[:target_url].to_s

    unless TRACKABLE_CLICK_KINDS.include?(kind)
      redirect_to shop_path(@shop), alert: "不正なクリック種別です"
      return
    end

    unless safe_redirect_target?(target_url, kind: kind)
      redirect_to shop_path(@shop), alert: "遷移先URLが不正です"
      return
    end

    @shop.shop_clicks.create!(kind: kind)

    redirect_to target_url, allow_other_host: true
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[track_click] validation failed: #{e.message}")
    redirect_to shop_path(@shop), alert: "クリック記録に失敗しました"
  rescue StandardError => e
    Rails.logger.warn("[track_click] #{e.class}: #{e.message}")
    redirect_to shop_path(@shop), alert: "クリック記録に失敗しました"
  end

  private

  def nearby_shops_for(shop)
    scope = Shop.approved
                .where.not(id: shop.id)

    if shop.smoking_area.present? && shop.smoking_area != "unknown"
      scope = scope.where(smoking_area: shop.smoking_area)
    end

    ranked_shops = if shop.latitude.present? && shop.longitude.present?
      rows = geocoded_recommendation_rows_for(shop).select do |row|
        row.fetch("distance").to_f <= 3.0 && recommendation_smoking_matches?(row, shop)
      end
      rank_geocoded_rows(rows, open_shop_ids: current_open_shop_ids)
    else
      rank_recommendation_shops(scope.select(RECOMMENDATION_RANKING_COLUMNS))
    end
    load_recommendation_shops(
      ranked_shops,
      origin_shop: shop,
      radius_km: shop.latitude.present? && shop.longitude.present? ? 3.0 : nil
    )
  end

  def same_genre_shops_for(shop)
    genre_value = shop.genre.to_s.strip
    genre_other_value = shop.genre_other.to_s.strip

    return [] if genre_value.blank? && genre_other_value.blank?

    if shop.latitude.present? && shop.longitude.present?
      rows = geocoded_recommendation_rows_for(shop).select do |row|
        recommendation_smoking_matches?(row, shop) &&
          ((genre_value.present? && row.fetch("genre").to_s == genre_value) ||
            (genre_other_value.present? && row.fetch("genre_other").to_s == genre_other_value))
      end
      ranked_shops = rank_geocoded_rows(rows, open_shop_ids: current_open_shop_ids)
    else
      scope = Shop.approved.where.not(id: shop.id)
      if shop.smoking_area.present? && shop.smoking_area != "unknown"
        scope = scope.where(smoking_area: shop.smoking_area)
      end
      genre_conditions = []
      genre_bindings = {}
      if genre_value.present?
        genre_conditions << "shops.genre = :genre_value"
        genre_bindings[:genre_value] = genre_value
      end
      if genre_other_value.present?
        genre_conditions << "shops.genre_other = :genre_other_value"
        genre_bindings[:genre_other_value] = genre_other_value
      end
      scope = scope.where(genre_conditions.join(" OR "), genre_bindings)
      scope = scope.select(RECOMMENDATION_RANKING_COLUMNS)
      ranked_shops = rank_recommendation_shops(scope)
    end
    load_recommendation_shops(
      ranked_shops,
      origin_shop: shop,
      radius_km: shop.latitude.present? && shop.longitude.present? ? 5.0 : nil
    )
  end

  def popular_shops_for(shop)
    if shop.latitude.present? && shop.longitude.present?
      click_counts = popular_click_counts
      ranked_shops = geocoded_recommendation_rows_for(shop)
        .sort_by { |row| popular_geocoded_sort_key(row, click_counts) }
        .first(6)
        .map { |row| RecommendationRankedShop.new(id: row.fetch("id").to_i) }
      clicks_count_by_id = ranked_shops.to_h do |ranked_shop|
        [ ranked_shop.id, click_counts.fetch(ranked_shop.id, 0) ]
      end

      return load_recommendation_shops(
        ranked_shops,
        origin_shop: shop,
        radius_km: 5.0,
        clicks_count_by_id: clicks_count_by_id
      )
    end

    click_counts_subquery = ShopClick
      .select("shop_clicks.shop_id, COUNT(*) AS clicks_count")
      .group("shop_clicks.shop_id")
      .to_sql
    clicks_count_sql = "COALESCE(popular_click_counts.clicks_count, 0)"

    ranking_scope = Shop.approved
                        .where.not(id: shop.id)
                        .joins(<<~SQL.squish)
                          LEFT JOIN (#{click_counts_subquery}) popular_click_counts
                            ON popular_click_counts.shop_id = shops.id
                        SQL

    if shop.latitude.present? && shop.longitude.present?
      ranking_scope = ranking_scope
        .where.not(latitude: nil, longitude: nil)
        .near(
          [ shop.latitude, shop.longitude ],
          5.0,
          units: :km,
          select: "shops.id, #{clicks_count_sql} AS clicks_count",
          select_bearing: false
        )
    else
      ranking_scope = ranking_scope.select(
        "shops.id",
        "#{clicks_count_sql} AS clicks_count"
      )
    end

    ranked_shops = ranking_scope
      .order(Arel.sql("
        clicks_count DESC,
        CASE WHEN shops.last_confirmed_on IS NOT NULL THEN 0 ELSE 1 END ASC,
        shops.last_confirmed_on DESC,
        shops.created_at DESC
      "))
      .limit(6)
      .to_a

    clicks_count_by_id = ranked_shops.to_h do |ranked_shop|
      [ ranked_shop.id, ranked_shop.clicks_count.to_i ]
    end

    load_recommendation_shops(
      ranked_shops,
      origin_shop: shop,
      radius_km: shop.latitude.present? && shop.longitude.present? ? 5.0 : nil,
      clicks_count_by_id: clicks_count_by_id
    )
  end

  def rank_recommendation_shops(scope)
    scope.to_a.sort_by do |candidate|
      [
        (candidate.respond_to?(:open_now?) && candidate.open_now?) ? 0 : 1,
        candidate.last_confirmed_on.present? ? 0 : 1,
        - (candidate.last_confirmed_on.to_i rescue 0),
        - candidate.created_at.to_i
      ]
    end.first(6)
  end

  def geocoded_recommendation_rows_for(shop)
    @geocoded_recommendation_rows ||= {}
    key = [
      shop.id,
      shop.latitude,
      shop.longitude
    ]

    @geocoded_recommendation_rows[key] ||= begin
      scope = Shop.approved
                  .where.not(id: shop.id)
                  .where.not(latitude: nil, longitude: nil)
      scope = scope.near(
        [ shop.latitude, shop.longitude ],
        5.0,
        units: :km,
        select: <<~SQL.squish,
          shops.id,
          shops.genre,
          shops.genre_other,
          shops.smoking_area,
          shops.last_confirmed_on,
          shops.created_at
        SQL
        select_bearing: false
      )
      Shop.connection.select_all(scope.to_sql)
    end
  end

  def current_open_shop_ids
    now = Time.zone.now
    key = [ now.wday, now.hour * 60 + now.min ]
    @current_open_shop_ids ||= {}
    @current_open_shop_ids[key] ||= ShopBusinessHourWindow
      .where(weekday: key.first)
      .where("opens_at_minute <= ? AND closes_at_minute > ?", key.last, key.last)
      .distinct
      .pluck(:shop_id)
      .to_set
  end

  def rank_geocoded_rows(rows, open_shop_ids:)
    rows.sort_by do |row|
      [
        open_shop_ids.include?(row.fetch("id").to_i) ? 0 : 1,
        row["last_confirmed_on"].present? ? 0 : 1,
        0,
        -recommendation_created_at_second(row.fetch("created_at"))
      ]
    end.first(6).map { |row| RecommendationRankedShop.new(id: row.fetch("id").to_i) }
  end

  def recommendation_smoking_matches?(row, shop)
    return true if shop.smoking_area.blank? || shop.smoking_area == "unknown"

    row.fetch("smoking_area").to_i == Shop.smoking_areas.fetch(shop.smoking_area)
  end

  def popular_click_counts
    @popular_click_counts ||= ShopClick.group(:shop_id).count
  end

  def popular_geocoded_sort_key(row, click_counts)
    id = row.fetch("id").to_i
    confirmed_on = row["last_confirmed_on"]

    [
      row.fetch("distance").to_f,
      -click_counts.fetch(id, 0),
      confirmed_on.present? ? 0 : 1,
      -recommendation_date_rank(confirmed_on),
      -recommendation_created_at_value(row.fetch("created_at"))
    ]
  end

  def recommendation_date_rank(value)
    return 0 if value.blank?
    return value.jd if value.respond_to?(:jd)

    Date.iso8601(value.to_s).jd
  end

  def recommendation_created_at_second(value)
    recommendation_created_at_value(value).floor
  end

  def recommendation_created_at_value(value)
    return value.to_f if value.respond_to?(:to_f) && !value.is_a?(String)

    Time.zone.parse(value.to_s).to_f
  end

  def load_recommendation_shops(ranked_shops, origin_shop:, radius_km:, clicks_count_by_id: nil)
    ranked_ids = ranked_shops.map(&:id)
    return [] if ranked_ids.empty?

    display_scope = Shop.where(id: ranked_ids)
    if radius_km
      display_scope = display_scope.near(
        [ origin_shop.latitude, origin_shop.longitude ],
        radius_km,
        units: :km
      )
    else
      display_scope = display_scope.select("shops.*")
    end

    if clicks_count_by_id.present?
      cases = clicks_count_by_id.map do |shop_id, count|
        "WHEN #{shop_id.to_i} THEN #{count.to_i}"
      end.join(" ")
      display_scope = display_scope.select(
        "CASE shops.id #{cases} ELSE 0 END AS clicks_count"
      )
    end

    shops_by_id = display_scope
      .preload(RECOMMENDATION_IMAGE_PRELOADS)
      .index_by(&:id)

    ranked_ids.filter_map { |shop_id| shops_by_id[shop_id] }
  end

  def related_articles_for(shop)
    return [] unless defined?(Article)

    area_text = [shop.area, shop.address, shop.nearest_station].compact.join(" ")
    shop_genres = [shop.genre.to_s.strip, shop.genre_other.to_s.strip].reject(&:blank?)

    area_keywords = []

    if area_text.include?("梅田") || area_text.include?("大阪駅") || area_text.include?("北新地")
      area_keywords << "梅田"
    end

    if area_text.include?("難波") || area_text.include?("なんば") || area_text.include?("心斎橋") || area_text.include?("日本橋")
      area_keywords << "難波"
      area_keywords << "なんば"
    end

    articles = Article.published.with_attached_eyecatch.limit(30).to_a

    scored_articles =
      articles.map do |article|
        text = [
          article.title,
          article.summary,
          article.admin_note
        ].compact.join(" ")

        score = 0

        area_keywords.each do |keyword|
          score += 10 if text.include?(keyword)
        end

        shop_genres.each do |genre|
          score += 6 if text.include?(genre)
        end

        score += 2 if article.eyecatch.attached?

        [article, score]
      end

    matched =
      scored_articles
        .select { |_article, score| score.positive? }
        .sort_by { |article, score| [-score, -(article.published_at || article.created_at).to_i] }
        .map(&:first)
        .first(3)

    return matched if matched.present?

    articles.first(3)
  end

  def shop_params
    params.require(:shop).permit(
      :name,
      :address,
      :public_store_details,
      :last_confirmed_on,
      :nearest_station,
      :phone,
      :smoking_area,
      :smoking_type,
      :genre,
      :genre_other,
      :thumbnail_kind,
      :thumbnail_index,
      :opening_hours_text,
      :holiday_hours_text,
      :closed_days_text,
      :special_hours_note,
      opening_hours_json: {},
      food_photos: [],
      interior_photos: [],
      exterior_photos: [],
      menu_photos: []
    )
  end

  def ip_hash_for_request
    raw = request.remote_ip.to_s
    salt = Rails.application.secret_key_base.to_s
    Digest::SHA256.hexdigest("#{salt}:#{raw}")
  end

  def normalize_phone(v)
    v.to_s.gsub(/[^0-9]/, "").presence
  end

  def contribution_count
    (session[:contribution_count] || 0).to_i
  end

  def increment_contribution!
    session[:contribution_count] = contribution_count + 1
  end

  def current_contribution_badge
    contribution_badge(contribution_count)
  end

  def contribution_badge(count)
    n = count.to_i
    return { name: "未達成", threshold: 0 } if n <= 0

    badges = [
      { threshold: 1, name: "はじめてのご協力" },
      { threshold: 5, name: "協力者" },
      { threshold: 10, name: "常連協力者" },
      { threshold: 30, name: "ベテラン協力者" },
      { threshold: 100, name: "レジェンド協力者" }
    ]

    badges.reverse_each do |b|
      return b if n >= b[:threshold]
    end

    { name: "未達成", threshold: 0 }
  end

  def contribution_message_and_badge
    count = contribution_count
    badge = contribution_badge(count)

    achieved_badge_name = nil

    if count > 0 && (count % 100 == 0)
      return ["🔥 ご協力回数 #{count}回達成！！本当にありがとうございます！！", nil]
    end

    thresholds = [1, 5, 10, 30, 100]
    if thresholds.include?(count)
      achieved_badge_name = badge[:name]
      return ["🎉 #{badge[:name]} バッジ獲得！ ご協力回数：#{count}回", achieved_badge_name]
    end

    ["ご協力ありがとうございます！ ご協力回数：#{count}回（バッジ：#{badge[:name]}）", nil]
  end

  def safe_redirect_target?(url, kind: nil)
    return false if url.blank?

    uri = URI.parse(url)

    if kind == "phone_click"
      return false unless uri.scheme == "tel"

      target_phone = normalize_phone(uri.opaque.presence || uri.path)
      shop_phone = normalize_phone(@shop&.phone)

      return false if target_phone.blank?
      return false if shop_phone.present? && target_phone != shop_phone

      return true
    end

    return false unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

    true
  rescue URI::InvalidURIError
    false
  end
end
