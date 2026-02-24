# frozen_string_literal: true

require "csv"

class Admin::ShopsController < Admin::BaseController
def index
@status = params[:status].presence || "pending"
@source = params[:source].to_s.presence

@per = (params[:per].presence || 50).to_i
@per = 50 if @per <= 0
@per = 500 if @per > 500

@page = params[:page].to_i
@page = 1 if @page <= 0

scope = Shop.order(created_at: :desc)

case @status
when "rejected"
scope = scope.where(rejected: true)
when "all"
# all
else
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

def edit
@shop = Shop.find(params[:id])
@status = params[:status].presence || "pending"
@source = params[:source].to_s.presence
@per = (params[:per].presence || 50).to_i
@page = (params[:page].presence || 1).to_i
end

def update
@shop = Shop.find(params[:id])

action = params[:commit_action].to_s
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

# ✅ CSVインポート（ヘッダー揺れ吸収 + エリア正規化）
def import
file = params[:file]
return redirect_to admin_shops_path, alert: "CSVファイルを選択してください" unless file

success = 0
failed = 0

area_map = {
"umeda" => "梅田",
"namba" => "難波",
"tennoji" => "天王寺",
"shinsaibashi" => "心斎橋",
"kyobashi" => "京橋",
"shinosaka" => "新大阪",
"yodoyabashi" => "淀屋橋",
"hommachi" => "本町"
}

normalize_str = lambda do |v|
return "" if v.nil?
s = v.is_a?(String) ? v : v.to_s
s = s.tr("０-９", "0-9")
s.gsub(/\A[[:space:]]+|[[:space:]]+\z/, "")
end

pick = lambda do |row, keys|
keys.each do |k|
v = row[k]
v = row[k.to_s] if v.nil? && k.is_a?(Symbol)
v = row[k.to_sym] if v.nil? && k.is_a?(String)
return v if v.present?
end
nil
end

CSV.foreach(file.path, headers: true) do |row|
begin
name = normalize_str.call(pick.call(row, [:name, "name", "店名"]))
phone = normalize_str.call(pick.call(row, [:phone, "phone", "電話番号"]))
address = normalize_str.call(pick.call(row, [:address, "address", "住所", "formatted_address"]))
opening = normalize_str.call(pick.call(row, [:opening_hours, "opening_hours", "営業時間", "hours"]))
area_raw = normalize_str.call(pick.call(row, [:area, "area", "エリア"]))

nearest_station = normalize_str.call(pick.call(row, [:nearest_station, "nearest_station", "最寄駅"]))
note = normalize_str.call(pick.call(row, [:note, "note", "メモ"]))

genre = normalize_str.call(pick.call(row, [:genre, "genre", "ジャンル"]))
genre_other = normalize_str.call(pick.call(row, [:genre_other, "genre_other", "ジャンルその他", "その他"]))

smoking_area_raw = normalize_str.call(pick.call(row, [:smoking_area, "smoking_area", "喫煙エリア"]))
smoking_area =
case smoking_area_raw
when "1" then "all_smoking"
when "2" then "separated"
else smoking_area_raw.presence
end

smoking_type_raw = normalize_str.call(pick.call(row, [:smoking_type, "smoking_type", "喫煙タイプ"]))
smoking_type =
case smoking_type_raw
when "1" then "both_ok"
when "2" then "electronic_only"
when "3" then "paper_only"
else smoking_type_raw.presence
end

last_raw = normalize_str.call(pick.call(row, [:last_confirmed_on, "last_confirmed_on", "最終確認日"]))
last_confirmed_on =
if last_raw.present?
if last_raw.match?(/\A\d{6}\z/)
year = ("20" + last_raw[0..1]).to_i
month = last_raw[2..3].to_i
day = last_raw[4..5].to_i
Date.new(year, month, day)
else
Date.parse(last_raw)
end
else
Date.current
end

area_key = area_raw.to_s.downcase
area = area_map[area_key] || area_raw

shop = Shop.new(
name: name,
phone: phone.presence,
address: address,
area: area.presence,
nearest_station: nearest_station.presence,
opening_hours: opening.presence,
note: note.presence,
genre: genre.presence,
genre_other: genre_other.presence,
smoking_area: smoking_area,
smoking_type: smoking_type,
last_confirmed_on: last_confirmed_on
)

shop.approved = false
shop.rejected = false if shop.respond_to?(:rejected=)

shop.save!
success += 1
rescue => e
Rails.logger.error "[CSV IMPORT ERROR] #{e.class}: #{e.message}"
failed += 1
end
end

redirect_to admin_shops_path, notice: "CSV取込完了：#{success}件成功 / #{failed}件失敗"
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