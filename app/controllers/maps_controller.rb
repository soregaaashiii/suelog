class MapsController < ApplicationController
  def index
    # 住所がある店だけ。承認済みだけにしたいなら approved を付ける
    @shops = Shop.where.not(address: [nil, ""]).order(created_at: :desc)
    @shops_count = @shops.size
  end
end
