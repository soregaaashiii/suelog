# /Users/kawamuratakuya/Desktop/吸えログデータ/dev/suelog/app/controllers/admin/shops_controller.rb
class Admin::ShopsController < Admin::BaseController
def index
@status = params[:status].presence || "pending"
@source = params[:source].to_s.presence

@per = (params[:per].presence || 50).to_i
@per = 50 if @per <= 0
@per = 500 if @per > 500 # 暴走防止

@page = params[:page].to_i
@page = 1 if @page <= 0

scope = Shop.order(created_at: :desc)

case @status
when "rejected"
scope = scope.where(rejected: true)
when "all"
# 全部
else
# 承認待ち（却下済みは除外）
scope = scope.where(approved: false).where(rejected: [false, nil])
end

if @source.present? && Shop.column_names.include?("source")
scope = scope.where(source: @source)
end

# ✅ 管理画面で写真を確実に出す（ActiveStorage eager load）
scope = scope.includes(
food_photos_attachments: :blob,
interior_photos_attachments: :blob,
exterior_photos_attachments: :blob,
menu_photos_attachments: :blob
)

# ✅ 総件数（ページング計算用）
@total_count = scope.count
@total_pages = (@total_count.to_f / @per).ceil
@total_pages = 1 if @total_pages <= 0

# ✅ offset/limit でページング
offset = (@page - 1) * @per
@shops = scope.offset(offset).limit(@per)
end

def approve
status = params[:status].presence || "pending"
shop = Shop.find(params[:id])

shop.update!(approved: true, rejected: false)

redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
notice: "承認しました"
rescue ActiveRecord::RecordInvalid => e
redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
alert: "承認に失敗しました：#{e.record.errors.full_messages.join(' / ')}"
end

def reject
status = params[:status].presence || "pending"
shop = Shop.find(params[:id])

shop.update!(approved: false, rejected: true)

redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
alert: "却下しました"
rescue ActiveRecord::RecordInvalid => e
redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
alert: "却下に失敗しました：#{e.record.errors.full_messages.join(' / ')}"
end

# ✅ 一括操作（approve / reject）
def bulk_update
status = params[:status].presence || "pending"

ids =
Array(params[:shop_ids]).presence ||
params[:shop_ids_csv].to_s.split(",")

ids = ids.map(&:to_i).uniq
op = params[:operation].to_s

if ids.empty?
return redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
alert: "店舗が選択されていません"
end

scope = Shop.where(id: ids)

case op
when "approve"
scope.update_all(approved: true, rejected: false, updated_at: Time.current)
redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
notice: "一括承認しました（#{ids.size}件）"
when "reject"
scope.update_all(approved: false, rejected: true, updated_at: Time.current)
redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
alert: "一括却下しました（#{ids.size}件）"
else
redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
alert: "不正な操作です"
end
end

# ✅ 承認待ちも編集
def edit
@shop = Shop.find(params[:id])
@status = params[:status].presence || "pending"
@source = params[:source].to_s.presence
@per = (params[:per].presence || 50).to_i
@page = (params[:page].presence || 1).to_i
end

# ✅ 編集ページで「更新」「更新して承認」「更新して却下」を1発でできる
def update
@shop = Shop.find(params[:id])

action = params[:commit_action].to_s # "update" / "approve" / "reject"
notice = "更新しました"

ActiveRecord::Base.transaction do
@shop.update!(shop_params)

case action
when "approve"
@shop.update!(approved: true, rejected: false)
notice = "更新して承認しました"
when "reject"
@shop.update!(approved: false, rejected: true)
notice = "更新して却下しました"
end
end

redirect_to admin_shops_path(status: params[:status], source: params[:source], per: params[:per], page: params[:page]),
notice: notice
rescue ActiveRecord::RecordInvalid => e
@status = params[:status].presence || "pending"
@source = params[:source].to_s.presence
@per = (params[:per].presence || 50).to_i
@page = (params[:page].presence || 1).to_i

flash.now[:alert] = e.record.errors.full_messages.join(" / ")
render :edit, status: :unprocessable_entity
end

private

def shop_params
params.require(:shop).permit(
:name, :address, :area, :nearest_station, :phone,
:opening_hours,
:genre, :genre_other, :note,
:smoking_area, :smoking_type
)
end
end