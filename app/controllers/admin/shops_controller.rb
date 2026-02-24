# frozen_string_literal: true

require "csv"

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

scope = scope.includes(
food_photos_attachments: :blob,
interior_photos_attachments: :blob,
exterior_photos_attachments: :blob,
menu_photos_attachments: :blob
)

@total_count = scope.count
@total_pages = (@total_count.to_f / @per).ceil
@total_pages = 1 if @total_pages <= 0

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
def import
file = params[:file]
return redirect_to admin_shops_path, alert: "CSVファイルを選択してください" unless file

require "csv"

success = 0
failed = 0

CSV.foreach(file.path, headers: true) do |row|
begin
attrs = row.to_hash.symbolize_keys

# =========================
# 全角 → 半角変換
# =========================
attrs.each do |k, v|
next unless v.is_a?(String)
attrs[k] = v.tr("０-９", "0-9").strip
end

# =========================
# 喫煙エリア 数字対応
# 1 = 席で喫煙可
# 2 = 喫煙所あり
# =========================
case attrs[:smoking_area].to_s
when "1"
attrs[:smoking_area] = "all_smoking"
when "2"
attrs[:smoking_area] = "separated"
end

# =========================
# 喫煙タイプ 数字対応
# 1 = 紙・加熱式OK
# 2 = 加熱式のみ
# 3 = 紙のみ
# =========================
case attrs[:smoking_type].to_s
when "1"
attrs[:smoking_type] = "both_ok"
when "2"
attrs[:smoking_type] = "electronic_only"
when "3"
attrs[:smoking_type] = "paper_only"
end

# =========================
# 6桁日付対応（例: 260223）
# =========================
if attrs[:last_confirmed_on].present?
date_str = attrs[:last_confirmed_on].to_s

if date_str.match?(/\A\d{6}\z/)
year = "20" + date_str[0..1]
month = date_str[2..3]
day = date_str[4..5]
attrs[:last_confirmed_on] = Date.new(year.to_i, month.to_i, day.to_i)
else
attrs[:last_confirmed_on] = Date.parse(date_str)
end
else
# 空なら今日にする（爆速用）
attrs[:last_confirmed_on] = Date.current
end

# =========================
# 保存処理
# =========================
shop = Shop.new(attrs)
shop.approved = false
shop.rejected = false if shop.respond_to?(:rejected=)

shop.save!
success += 1

rescue => e
Rails.logger.error "[CSV IMPORT ERROR] #{e.message}"
failed += 1
end
end

redirect_to admin_shops_path,
notice: "CSV取込完了：#{success}件成功 / #{failed}件失敗"
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