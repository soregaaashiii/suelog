# /Users/kawamuratakuya/Desktop/吸えログデータ/dev/suelog/app/controllers/maps_controller.rb
# frozen_string_literal: true

class MapsController < ApplicationController
def index
@shops = Shop
.approved
.where.not(latitude: nil, longitude: nil)
.order(created_at: :desc)

@shops_count = @shops.size
end
end