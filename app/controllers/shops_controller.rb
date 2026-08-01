# /Users/kawamuratakuya/dev/suelog/app/controllers/shops_controller.rb
# frozen_string_literal: true

class ShopsController < ApplicationController
  require "digest"

  helper_method :contribution_count, :current_contribution_badge

  TRACKABLE_CLICK_KINDS = %w[
    phone_click
    map_click
    affiliate_click
  ].freeze

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
                .includes(
                  food_photos_attachments: :blob,
                  interior_photos_attachments: :blob,
                  exterior_photos_attachments: :blob,
                  menu_photos_attachments: :blob
                )

    if shop.smoking_area.present? && shop.smoking_area != "unknown"
      scope = scope.where(smoking_area: shop.smoking_area)
    end

    nearby =
      if shop.latitude.present? && shop.longitude.present?
        geo_scope = scope.where.not(latitude: nil, longitude: nil)
        geo_scope.near([shop.latitude, shop.longitude], 3.0, units: :km)
      else
        scope
      end

    sorted = nearby.to_a.sort_by do |s|
      [
        (s.respond_to?(:open_now?) && s.open_now?) ? 0 : 1,
        s.last_confirmed_on.present? ? 0 : 1,
        - (s.last_confirmed_on.to_i rescue 0),
        - s.created_at.to_i
      ]
    end

    sorted.first(6)
  end

  def same_genre_shops_for(shop)
    genre_value = shop.genre.to_s.strip
    genre_other_value = shop.genre_other.to_s.strip

    return [] if genre_value.blank? && genre_other_value.blank?

    scope = Shop.approved
                .where.not(id: shop.id)
                .includes(
                  food_photos_attachments: :blob,
                  interior_photos_attachments: :blob,
                  exterior_photos_attachments: :blob,
                  menu_photos_attachments: :blob
                )

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

    if shop.latitude.present? && shop.longitude.present?
      scope = scope.where.not(latitude: nil, longitude: nil)
                   .near([shop.latitude, shop.longitude], 5.0, units: :km)
    end

    sorted = scope.to_a.sort_by do |s|
      [
        (s.respond_to?(:open_now?) && s.open_now?) ? 0 : 1,
        s.last_confirmed_on.present? ? 0 : 1,
        - (s.last_confirmed_on.to_i rescue 0),
        - s.created_at.to_i
      ]
    end

    sorted.first(6)
  end

  def popular_shops_for(shop)
    legacy_popular_shops_for(shop)
  end

  def legacy_popular_shops_for(shop)
    scope = Shop.approved
                .where.not(id: shop.id)
                .left_joins(:shop_clicks)
                .includes(
                  food_photos_attachments: :blob,
                  interior_photos_attachments: :blob,
                  exterior_photos_attachments: :blob,
                  menu_photos_attachments: :blob
                )
                .select(
                  "shops.*",
                  "COUNT(shop_clicks.id) AS clicks_count"
                )
                .group("shops.id")

    if shop.latitude.present? && shop.longitude.present?
      scope = scope.where.not(latitude: nil, longitude: nil)
                   .near([shop.latitude, shop.longitude], 5.0, units: :km)
    end

    scope
      .order(Arel.sql("
        COUNT(shop_clicks.id) DESC,
        CASE WHEN shops.last_confirmed_on IS NOT NULL THEN 0 ELSE 1 END ASC,
        shops.last_confirmed_on DESC,
        shops.created_at DESC
      "))
      .limit(6)
      .to_a
  end

  def optimized_popular_shops_for(shop)
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
        #{clicks_count_sql} DESC,
        CASE WHEN shops.last_confirmed_on IS NOT NULL THEN 0 ELSE 1 END ASC,
        shops.last_confirmed_on DESC,
        shops.created_at DESC
      "))
      .limit(6)
      .to_a

    return [] if ranked_shops.empty?

    ranked_ids = ranked_shops.map(&:id)
    clicks_count_sql = ranked_shops.map do |ranked_shop|
      "WHEN #{ranked_shop.id.to_i} THEN #{ranked_shop.clicks_count.to_i}"
    end.join(" ")

    display_scope = Shop.where(id: ranked_ids)
    if shop.latitude.present? && shop.longitude.present?
      display_scope = display_scope.near(
        [ shop.latitude, shop.longitude ],
        5.0,
        units: :km
      )
    else
      display_scope = display_scope.select("shops.*")
    end

    display_scope = display_scope
      .select("CASE shops.id #{clicks_count_sql} ELSE 0 END AS clicks_count")
      .includes(
        food_photos_attachments: :blob,
        interior_photos_attachments: :blob,
        exterior_photos_attachments: :blob,
        menu_photos_attachments: :blob
      )

    shops_by_id = display_scope.index_by(&:id)
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
