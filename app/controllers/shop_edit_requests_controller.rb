# frozen_string_literal: true

class ShopEditRequestsController < ApplicationController
def new
@shop = Shop.find(params[:shop_id])

@req = @shop.shop_edit_requests.build(
proposed_name: @shop.name,
proposed_address: @shop.address,
proposed_nearest_station: @shop.nearest_station,
proposed_phone: @shop.phone,
proposed_smoking_area: @shop.smoking_area,
proposed_smoking_type: @shop.smoking_type,
genre: @shop.genre,
genre_other: @shop.genre_other,
proposed_thumbnail_kind: (@shop.thumbnail_kind.presence || "auto"),
proposed_thumbnail_index: (@shop.thumbnail_index.presence || 1),
note: @shop.note,
proposed_opening_hours_json: (@shop.opening_hours_data || {})
)

assign_simple_hours_from_shop!(@req, @shop)
end

def create
@shop = Shop.find(params[:shop_id])

@req = @shop.shop_edit_requests.build(
proposed_name: @shop.name,
proposed_address: @shop.address,
proposed_nearest_station: @shop.nearest_station,
proposed_phone: @shop.phone,
proposed_smoking_area: @shop.smoking_area,
proposed_smoking_type: @shop.smoking_type,
genre: @shop.genre,
genre_other: @shop.genre_other,
proposed_thumbnail_kind: (@shop.thumbnail_kind.presence || "auto"),
proposed_thumbnail_index: (@shop.thumbnail_index.presence || 1),
note: @shop.note,
proposed_opening_hours_json: (@shop.opening_hours_data || {})
)

assign_simple_hours_from_shop!(@req, @shop)
@req.assign_attributes(req_params)
@req.status = :pending if @req.respond_to?(:status)

@req.proposed_name = @shop.name if blankish?(@req.proposed_name)
@req.proposed_address = @shop.address if blankish?(@req.proposed_address)
@req.proposed_nearest_station = @shop.nearest_station if blankish?(@req.proposed_nearest_station)
@req.proposed_phone = @shop.phone if blankish?(@req.proposed_phone)

@req.proposed_smoking_area = @shop.smoking_area if blankish?(@req.proposed_smoking_area)
@req.proposed_smoking_type = @shop.smoking_type if blankish?(@req.proposed_smoking_type)

if blankish?(@req.genre)
@req.genre = @shop.genre
@req.genre_other = @shop.genre_other
end

if @req.genre.to_s != "その他" && blankish?(@req.genre_other)
@req.genre_other = @shop.genre_other
end

if @req.respond_to?(:proposed_last_confirmed_on) && @req.proposed_last_confirmed_on.blank?
@req.proposed_last_confirmed_on = nil
end

@req.note = @shop.note if blankish?(@req.note)

if blankish?(@req.proposed_thumbnail_kind)
@req.proposed_thumbnail_kind = (@shop.thumbnail_kind.presence || "auto")
end

if @req.proposed_thumbnail_index.blank? || @req.proposed_thumbnail_index.to_i <= 0
@req.proposed_thumbnail_index = (@shop.thumbnail_index.presence || 1)
end

if blankish?(@req.proposed_opening_hours_text)
@req.proposed_opening_hours_text = @shop.opening_hours_text
end

if blankish?(@req.proposed_holiday_hours_text)
@req.proposed_holiday_hours_text = @shop.holiday_hours_text
end

if blankish?(@req.proposed_closed_days_text)
@req.proposed_closed_days_text = @shop.closed_days_text
end

if @req.proposed_opening_hours_json.blank? || @req.proposed_opening_hours_json.to_h.empty?
@req.proposed_opening_hours_json = (@shop.opening_hours_data || {})
end

if @req.save
increment_contribution!
redirect_to done_shop_shop_edit_requests_path(@shop), notice: contribution_message
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
:proposer_name,
:note,
:proposed_name,
:proposed_address,
:proposed_last_confirmed_on,
:proposed_nearest_station,
:proposed_phone,
:proposed_smoking_area,
:proposed_smoking_type,
:proposed_area,
:genre,
:genre_other,
:proposed_thumbnail_kind,
:proposed_thumbnail_index,
:proposed_opening_hours_text,
:proposed_holiday_hours_text,
:proposed_closed_days_text,
proposed_opening_hours_json: {},
food_photos: [],
interior_photos: [],
exterior_photos: [],
menu_photos: []
)
end

def assign_simple_hours_from_shop!(req, shop)
req.proposed_opening_hours_text = shop.opening_hours_text
req.proposed_holiday_hours_text = shop.holiday_hours_text
req.proposed_closed_days_text = shop.closed_days_text
end

def blankish?(value)
value.nil? || value.to_s.strip == ""
end

def increment_contribution!
session[:contribution_count] ||= 0
session[:contribution_count] += 1
end

def contribution_badge_data(count)
n = count.to_i
return { name: "未達成", threshold: 0 } if n <= 0

badges = [
{ threshold: 1, name: "はじめてのご協力" },
{ threshold: 5, name: "協力者" },
{ threshold: 10, name: "常連協力者" },
{ threshold: 30, name: "ベテラン協力者" },
{ threshold: 100, name: "レジェンド協力者" }
]

badges.reverse_each do |badge|
return badge if n >= badge[:threshold]
end

{ name: "未達成", threshold: 0 }
end

def contribution_message
count = session[:contribution_count].to_i
badge = contribution_badge_data(count)

return "🔥 #{count}回達成！超ご協力ありがとうございます！！" if count.positive? && (count % 100).zero?

case count
when 1, 5, 10, 30, 100
"🎉 #{badge[:name]}バッジ獲得！ありがとうございます！"
else
"ご協力ありがとうございます！"
end
end
end