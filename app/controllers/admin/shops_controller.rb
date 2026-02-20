# app/controllers/admin/shops_controller.rb
class Admin::ShopsController < Admin::BaseController
def index
@status = params[:status].presence || "pending"

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

# ✅ 管理画面で写真を確実に出す（ActiveStorage eager load）
scope = scope.includes(
food_photos_attachments: :blob,
interior_photos_attachments: :blob,
exterior_photos_attachments: :blob,
menu_photos_attachments: :blob
)

@shops = scope
end

def approve
status = params[:status].presence || "pending"

shop = Shop.find(params[:id])

# ✅ note含め、登録時点の内容をそのまま残して「承認フラグだけ」更新
shop.update!(approved: true, rejected: false)

redirect_to admin_shops_path(status: status), notice: "承認しました"
rescue ActiveRecord::RecordInvalid => e
redirect_to admin_shops_path(status: status),
alert: "承認に失敗しました：#{e.record.errors.full_messages.join(' / ')}"
end

def reject
status = params[:status].presence || "pending"

shop = Shop.find(params[:id])
shop.update!(approved: false, rejected: true)

redirect_to admin_shops_path(status: status), alert: "却下しました"
rescue ActiveRecord::RecordInvalid => e
redirect_to admin_shops_path(status: status),
alert: "却下に失敗しました：#{e.record.errors.full_messages.join(' / ')}"
end
end