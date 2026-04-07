# /Users/kawamuratakuya/dev/suelog/app/controllers/shops_controller.rb
# frozen_string_literal: true

class ShopsController < ApplicationController
  require "digest"

  helper_method :contribution_count, :current_contribution_badge

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

    @shops = scope
  end

  def show
    @shop = Shop.find(params[:id])

    track_page_view(shop: @shop)

    @review = Review.new
    @approved_reviews = @shop.reviews.approved.order(created_at: :desc)

    ip_hash = ip_hash_for_request
    @my_review = @shop.reviews.find_by(ip_hash: ip_hash)
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

  private

  def shop_params
    params.require(:shop).permit(
      :name,
      :area,
      :address,
      :note,
      :last_confirmed_on,
      :nearest_station,
      :phone,
      :smoking_area,
      :smoking_type,
      :genre,
      :genre_other,
      :thumbnail_kind,
      :thumbnail_index,
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
end