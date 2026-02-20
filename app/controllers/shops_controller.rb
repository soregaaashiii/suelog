# /app/controllers/shops_controller.rb
class ShopsController < ApplicationController
require "digest"

def index
redirect_to root_path, status: :moved_permanently
end

# ✅ 近くの店：緯度経度がある店だけ
# ✅ lat/lngが来たら半径0.5kmに絞る
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
redirect_to shop_path(@shop), notice: "投稿が完了しました。反映されるまでお待ちください。"
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
:name, :area, :address, :note, :last_confirmed_on,
:nearest_station, :phone,
:smoking_area, :smoking_type,
:genre, :genre_other,
:opening_hours,
:thumbnail_kind, :thumbnail_index,
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
end