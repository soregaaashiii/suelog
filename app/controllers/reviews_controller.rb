# app/controllers/reviews_controller.rb
class ReviewsController < ApplicationController
  require "digest"

  before_action :set_shop, only: [:create]
  before_action :set_review, only: [:edit, :update]
  before_action :ensure_owner_by_ip!, only: [:edit, :update]

  # POST /shops/:shop_id/reviews
  def create
    ip_hash = ip_hash_for_request

    # ✅ 同一IPは「同一店舗に1件だけ」
    existing = @shop.reviews.find_by(ip_hash: ip_hash)
    if existing.present?
      redirect_to shop_path(@shop, anchor: "review-form"),
                  alert: "この店舗には既に口コミを投稿済みです。編集する場合は下の「あなたの口コミを編集」から更新してください。"
      return
    end

    @review = @shop.reviews.build(review_params)
    @review.approved = false
    @review.ip_hash = ip_hash

    if @review.save
      # ✅ ご協力回数（同一IPハッシュの投稿数）
      contribution_count = Review.where(ip_hash: ip_hash).count

      redirect_to shop_path(@shop),
                  notice: "口コミありがとうございます！ご協力 #{contribution_count}回目 🙌 反映されるまでお待ちください。"
    else
      @approved_reviews = @shop.reviews.approved.order(created_at: :desc)
      render "shops/show", status: :unprocessable_entity
    end
  end

  # GET /reviews/:id/edit
  def edit
    @shop = @review.shop
  end

  # PATCH /reviews/:id
  def update
    @shop = @review.shop

    # ✅ 編集したら再審査（承認OFFに戻す）
    if @review.update(review_params.merge(approved: false))
      contribution_count = Review.where(ip_hash: @review.ip_hash).count

      redirect_to shop_path(@shop, anchor: "review-form"),
                  notice: "口コミの更新ありがとうございます！ご協力 #{contribution_count}回目 🙌（再審査になります）"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_shop
    @shop = Shop.find(params[:shop_id])
  end

  def set_review
    @review = Review.find(params[:id])
  end

  def review_params
    params.require(:review).permit(:rating, :comment, :author_name)
  end

  # ✅ 本人（同一IP）のみ編集可
  def ensure_owner_by_ip!
    return if @review.ip_hash.present? && @review.ip_hash == ip_hash_for_request

    redirect_to shop_path(@review.shop, anchor: "review-form"),
                alert: "この口コミは編集できません。"
  end

  # ✅ IPは生IPで保存しない（ハッシュ化）
  def ip_hash_for_request
    raw = request.remote_ip.to_s
    salt = Rails.application.secret_key_base.to_s
    Digest::SHA256.hexdigest("#{salt}:#{raw}")
  end
end