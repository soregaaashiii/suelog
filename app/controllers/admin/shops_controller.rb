# /Users/kawamuratakuya/dev/suelog/app/controllers/admin/shops_controller.rb
# frozen_string_literal: true

require "csv"
require "json"
require "date"

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
when "unverified"
  scope = scope.where(smoking_unverified: true)
when "hold"
  scope = scope.where(on_hold: true)
else
  scope = scope.where(approved: false).where(rejected: [false, nil]).where(on_hold: [false, nil])
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

def holds
  @shops = Shop
    .where(on_hold: true)
    .order(held_at: :desc, updated_at: :desc)
end

def show
@shop = Shop.find(params[:id])
@status = params[:status].presence || "pending"
@source = params[:source].to_s.presence
@per = (params[:per].presence || 50).to_i
@page = (params[:page].presence || 1).to_i

@duplicate_candidates =
if @shop.respond_to?(:duplicate_candidates)
@shop.duplicate_candidates(limit: 10)
else
[]
end
end

def approve
status = params[:status].presence || "pending"
shop = Shop.find(params[:id])

if Shop.duplicate_exists_for_import?(
     {
       name: shop.name,
       address: shop.address,
       phone: shop.phone
     },
     exclude_id: shop.id
   )
  redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
              alert: "重複の可能性があるため承認できません。詳細から重複候補を確認してください。"
  return
end

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
approved_count = 0
skipped_count = 0

scope.find_each do |shop|
  if Shop.duplicate_exists_for_import?(
       {
         name: shop.name,
         address: shop.address,
         phone: shop.phone
       },
       exclude_id: shop.id
     )
    Rails.logger.info("[SKIP DUPLICATE APPROVE] #{shop.id}")
    skipped_count += 1
    next
  end

  shop.update!(approved: true, rejected: false)
  approved_count += 1
end

message = "一括承認しました（#{approved_count}件）"
message += " / 重複の可能性でスキップ（#{skipped_count}件）" if skipped_count.positive?

redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
            notice: message
when "reject"
scope.update_all(approved: false, rejected: true, updated_at: Time.current)
redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
alert: "一括却下しました（#{ids.size}件）"
when "unverify"
scope.update_all(smoking_unverified: false, updated_at: Time.current)
redirect_to admin_shops_path(status: status, source: params[:source], per: params[:per], page: params[:page]),
notice: "未確認を解除しました（#{ids.size}件）"
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
Rails.logger.warn("SHOP_PARAMS_RAW=#{params[:shop].inspect}")

action = params[:commit_action].to_s
notice = "更新しました"

ActiveRecord::Base.transaction do
@shop.update!(shop_params)

case action
when "approve"
  if Shop.duplicate_exists_for_import?(
       {
         name: @shop.name,
         address: @shop.address,
         phone: @shop.phone
       },
       exclude_id: @shop.id
     )
    raise ActiveRecord::RecordInvalid.new(@shop.tap { |s| s.errors.add(:base, "重複の可能性があるため承認できません。詳細から重複候補を確認してください。") })
  end

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

  success = 0
  failed = 0
  skipped_duplicates = 0
  skipped_blank = 0
  processed_rows = 0
  raw_rows = 0
  error_messages = []

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

  map_smoking_area = lambda do |raw|
    s = normalize_str.call(raw)
    return nil if s.blank?

    case s
    when "0" then "separated"
    when "1" then "all_smoking"
    when "2" then "separated"
    else s.presence
    end
  end

  map_smoking_type = lambda do |raw|
    s = normalize_str.call(raw)
    return nil if s.blank?

    case s
    when "0" then "both_ok"
    when "1" then "electronic_only"
    when "2" then "paper_only"
    when "3" then "paper_only"
    else s.presence
    end
  end

  begin
    csv_text = file.read
    csv_text = csv_text.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    csv_text.sub!(/\A\uFEFF/, "")

    rows = CSV.parse(csv_text, headers: true)

    if rows.empty?
      return redirect_to admin_shops_path, alert: "CSVのデータ行が0件です。ヘッダだけ、またはCSV形式が不正です。"
    end

    Rails.logger.info("[CSV IMPORT] headers=#{rows.headers.inspect}")

    rows.each_with_index do |row, idx|
      raw_rows += 1

      begin
        row_hash = row.to_h

        if row_hash.values.all? { |v| normalize_str.call(v).blank? }
          skipped_blank += 1
          Rails.logger.info("[CSV IMPORT SKIP BLANK] line=#{idx + 2}")
          next
        end

        name = normalize_str.call(pick.call(row, [:name, "name", "店名"]))
        phone = normalize_str.call(pick.call(row, [:phone, "phone", "電話番号"]))
        address = normalize_str.call(pick.call(row, [:address, "address", "住所", "formatted_address"]))

        if name.blank? && address.blank? && phone.blank?
          skipped_blank += 1
          Rails.logger.info("[CSV IMPORT SKIP EMPTY KEY FIELDS] line=#{idx + 2} row=#{row_hash.inspect}")
          next
        end

        processed_rows += 1

        attrs = {
          name: name,
          address: address,
          phone: phone
        }

        if Shop.duplicate_exists_for_import?(attrs)
          skipped_duplicates += 1
          Rails.logger.info("[SKIP DUPLICATE] line=#{idx + 2} #{name} / #{address}")
          next
        end

        opening_hours_text = normalize_str.call(
          pick.call(row, [:opening_hours_text, "opening_hours_text", "通常営業時間", "営業時間テキスト"])
        )
        holiday_hours_text = normalize_str.call(
          pick.call(row, [:holiday_hours_text, "holiday_hours_text", "祝日営業時間"])
        )
        closed_days_text = normalize_str.call(
          pick.call(row, [:closed_days_text, "closed_days_text", "定休日"])
        )

        opening_json_raw = pick.call(row, [:opening_hours_json, "opening_hours_json", "営業時間JSON"])
        opening_text_legacy = normalize_str.call(
          pick.call(row, [:opening_hours, "opening_hours", "営業時間", "hours"])
        )

        opening_json =
          if opening_json_raw.present?
            begin
              parsed = JSON.parse(opening_json_raw.to_s)
              OpeningHoursParser.normalize_json(parsed)
            rescue JSON::ParserError
              OpeningHoursParser.parse_legacy_text(opening_text_legacy)
            end
          elsif opening_text_legacy.present?
            OpeningHoursParser.parse_legacy_text(opening_text_legacy)
          else
            {}
          end

        area_raw = normalize_str.call(pick.call(row, [:area, "area", "エリア"]))
        nearest_station = normalize_str.call(pick.call(row, [:nearest_station, "nearest_station", "最寄駅"]))
        note = normalize_str.call(pick.call(row, [:note, "note", "メモ"]))
        public_store_details = normalize_str.call(
          pick.call(row, [:public_store_details, "public_store_details", "店舗詳細", "詳細"])
        )

        genre = normalize_str.call(pick.call(row, [:genre, "genre", "ジャンル"]))
        genre_other = normalize_str.call(pick.call(row, [:genre_other, "genre_other", "ジャンルその他", "その他"]))

        smoking_area = map_smoking_area.call(pick.call(row, [:smoking_area, "smoking_area", "喫煙エリア"]))
        smoking_type = map_smoking_type.call(pick.call(row, [:smoking_type, "smoking_type", "喫煙タイプ"]))

        tabelog_url = normalize_str.call(
          pick.call(row, [:tabelog_url, "tabelog_url", "食べログURL", "tabelog"])
        )
        hotpepper_url = normalize_str.call(
          pick.call(row, [:hotpepper_url, "hotpepper_url", "ホットペッパーURL", "hotpepper"])
        )

        last_raw = normalize_str.call(
          pick.call(row, [:last_confirmed_on, "last_confirmed_on", "最終確認日"])
        )

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
          opening_hours_text: opening_hours_text.presence,
          holiday_hours_text: holiday_hours_text.presence,
          closed_days_text: closed_days_text.presence,
          opening_hours_json: opening_json,
          note: note.presence,
          public_store_details: public_store_details.presence,
          genre: genre.presence,
          genre_other: genre_other.presence,
          smoking_area: smoking_area,
          smoking_type: smoking_type,
          tabelog_url: tabelog_url.presence,
          hotpepper_url: hotpepper_url.presence,
          last_confirmed_on: last_confirmed_on
        )

        if shop.opening_hours_text.blank? && shop.respond_to?(:derived_opening_hours_text, true)
          derived_text = shop.send(:derived_opening_hours_text)
          shop.opening_hours_text = derived_text if derived_text.present?
        end

        if shop.closed_days_text.blank? && shop.respond_to?(:derived_closed_days_text, true)
          derived_closed = shop.send(:derived_closed_days_text)
          shop.closed_days_text = derived_closed if derived_closed.present?
        end

        shop.approved = false
        shop.rejected = false if shop.respond_to?(:rejected=)

        shop.save!
        success += 1
      rescue => e
  failed += 1

  detail =
    if e.respond_to?(:record) && e.record.present?
      e.record.errors.full_messages.join(", ")
    else
      e.message
    end

  message = "#{idx + 2}行目: #{e.class} - #{detail}"
  error_messages << message
  Rails.logger.error("[CSV IMPORT ERROR] #{message} row=#{row.to_h.inspect}")
end
    end

    if processed_rows.zero?
      return redirect_to admin_shops_path,
                         alert: "CSVのデータ行を処理できませんでした。ヘッダ名・文字コード・保存形式を確認してください。"
    end

    notice_message = "CSV取込完了：#{success}件成功 / #{failed}件失敗 / 重複#{skipped_duplicates}件スキップ / 空行#{skipped_blank}件スキップ / 対象#{processed_rows}件"
    redirect_to admin_shops_path, notice: notice_message, alert: error_messages.first(5).join(" / ").presence
  rescue CSV::MalformedCSVError => e
    redirect_to admin_shops_path, alert: "CSV形式が不正です: #{e.message}"
  rescue => e
    redirect_to admin_shops_path, alert: "インポート中にエラーが発生しました: #{e.class} - #{e.message}"
  end
end

private

def shop_params
params.require(:shop).permit(
:name,
:address,
:area,
:nearest_station,
:phone,
:genre,
:genre_other,
:note,
:public_store_details,
:smoking_area,
:smoking_type,
:smoking_unverified,
:last_confirmed_on,
:opening_hours_text,
:holiday_hours_text,
:closed_days_text,
:tabelog_url,
:hotpepper_url,
opening_hours_json: {}
)
end
end