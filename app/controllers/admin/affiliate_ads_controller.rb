class Admin::AffiliateAdsController < ApplicationController
  before_action :set_affiliate_ad, only: [:edit, :update, :destroy]

  def index
    @affiliate_ads = AffiliateAd.order(created_at: :desc)
  end

  def new
    @affiliate_ad = AffiliateAd.new(active: true)
  end

  def create
    @affiliate_ad = AffiliateAd.new(affiliate_ad_params)

    if @affiliate_ad.save
      redirect_to admin_affiliate_ads_path, notice: "広告を作成しました"
    else
      Rails.logger.debug(@affiliate_ad.errors.full_messages)
      render :new
    end
  end

  def edit
  end

  def update
    if @affiliate_ad.update(affiliate_ad_params)
      redirect_to admin_affiliate_ads_path, notice: "広告を更新しました"
    else
      Rails.logger.debug(@affiliate_ad.errors.full_messages)
      render :edit
    end
  end

  def destroy
    @affiliate_ad.destroy
    redirect_to admin_affiliate_ads_path, notice: "広告を削除しました"
  end

  private

  def set_affiliate_ad
    @affiliate_ad = AffiliateAd.find(params[:id])
  end

  def affiliate_ad_params
    params.require(:affiliate_ad).permit(
      :key,
      :url,
      :image,
      :image_path,
      :active
    )
  end
end