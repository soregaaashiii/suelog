# app/controllers/shop_edit_requests_controller.rb
class ShopEditRequestsController < ApplicationController
def new
@shop = Shop.find(params[:shop_id])

# ✅ 現状値を初期値として入れて表示（変更しない場合のUX）
# ✅ note も初期値に「現在の店舗メモ」を入れる（ここが重要）
@req = @shop.shop_edit_requests.build(
proposed_name: @shop.name,
proposed_address: @shop.address,
proposed_nearest_station: @shop.nearest_station,
proposed_phone: @shop.phone,
proposed_opening_hours: @shop.opening_hours,
proposed_smoking_area: @shop.smoking_area,
proposed_smoking_type: @shop.smoking_type,
genre: @shop.genre,
genre_other: @shop.genre_other,
proposed_thumbnail_kind: (@shop.thumbnail_kind.presence || "auto"),
proposed_thumbnail_index: (@shop.thumbnail_index.presence || 1),
note: @shop.note # ✅ 追加
# proposed_last_confirmed_on は空でOK
)
end

def create
@shop = Shop.find(params[:shop_id])

# ✅ 現状値を土台にする（空なら現状維持）
# ✅ note も土台に含める（空送信＝変更しない）
@req = @shop.shop_edit_requests.build(
proposed_name: @shop.name,
proposed_address: @shop.address,
proposed_nearest_station: @shop.nearest_station,
proposed_phone: @shop.phone,
proposed_opening_hours: @shop.opening_hours,
proposed_smoking_area: @shop.smoking_area,
proposed_smoking_type: @shop.smoking_type,
genre: @shop.genre,
genre_other: @shop.genre_other,
proposed_thumbnail_kind: (@shop.thumbnail_kind.presence || "auto"),
proposed_thumbnail_index: (@shop.thumbnail_index.presence || 1),
note: @shop.note # ✅ 追加
)

# ✅ ユーザー入力で上書き（写真もここで attach される）
@req.assign_attributes(req_params)
@req.status = :pending if @req.respond_to?(:status)

# =========================================================
# ✅ 空で送られたら変更しない（現状値に戻す）
# =========================================================

# 文字列系（空/空白だけなら戻す）
@req.proposed_name = @shop.name if blankish?(@req.proposed_name)
@req.proposed_address = @shop.address if blankish?(@req.proposed_address)
@req.proposed_nearest_station = @shop.nearest_station if blankish?(@req.proposed_nearest_station)
@req.proposed_phone = @shop.phone if blankish?(@req.proposed_phone)
@req.proposed_opening_hours = @shop.opening_hours if blankish?(@req.proposed_opening_hours)

# セレクト系（"" が来るやつ）
@req.proposed_smoking_area = @shop.smoking_area if blankish?(@req.proposed_smoking_area)
@req.proposed_smoking_type = @shop.smoking_type if blankish?(@req.proposed_smoking_type)

# ジャンル（空なら戻す）
if blankish?(@req.genre)
@req.genre = @shop.genre
@req.genre_other = @shop.genre_other
end

# 「その他」じゃないのに genre_other が空で送られても現状維持
if @req.genre.to_s != "その他" && blankish?(@req.genre_other)
@req.genre_other = @shop.genre_other
end

# 日付（空なら「変更しない」＝nilのまま）
if @req.respond_to?(:proposed_last_confirmed_on) && @req.proposed_last_confirmed_on.blank?
@req.proposed_last_confirmed_on = nil
end

# ✅ メモ（note）も「空なら変更しない」に統一（ここが今回の本丸）
@req.note = @shop.note if blankish?(@req.note)

# ✅ サムネ（依頼側）
if blankish?(@req.proposed_thumbnail_kind)
@req.proposed_thumbnail_kind = (@shop.thumbnail_kind.presence || "auto")
end

if @req.proposed_thumbnail_index.blank? || @req.proposed_thumbnail_index.to_i <= 0
@req.proposed_thumbnail_index = (@shop.thumbnail_index.presence || 1)
end

if @req.save
redirect_to done_shop_shop_edit_requests_path(@shop)
else
render :new, status: :unprocessable_entity
end
end

def done
@shop = Shop.find(params[:shop_id])
end

private

def req_params
params.require(:shop_edit_request).permit(
:proposer_name, :note,
:proposed_name, :proposed_address, :proposed_last_confirmed_on,
:proposed_nearest_station, :proposed_phone,
:proposed_smoking_area, :proposed_smoking_type,

:proposed_area, 
:genre, :genre_other,
:proposed_opening_hours,

# ✅ サムネ候補
:proposed_thumbnail_kind, :proposed_thumbnail_index,
:proposed_area, 
# ✅ 写真（編集依頼に添付）
food_photos: [],
interior_photos: [],
exterior_photos: [],
menu_photos: []
)
end

# ✅ 空 or 空白だけ を true 扱いにする
def blankish?(v)
v.nil? || v.to_s.strip == ""
end
end