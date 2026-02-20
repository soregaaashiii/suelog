# app/controllers/admin/shop_edit_requests_controller.rb
class Admin::ShopEditRequestsController < Admin::BaseController
before_action :set_req, only: [:show, :approve, :reject]

def index
scope = ShopEditRequest
.includes(
:shop,
food_photos_attachments: :blob,
interior_photos_attachments: :blob,
exterior_photos_attachments: :blob,
menu_photos_attachments: :blob
)
.order(created_at: :desc)

scope = scope.where(status: 0) if params[:status] == "pending"
@edit_requests = scope
end

def show
@shop = @req.shop
end

def approve
req = ShopEditRequest.find(params[:id])
shop = @req.shop
attrs = build_shop_attrs_from_request(@req)

# エリア（空欄は反映しない）
area = req.proposed_area.to_s.strip
attrs[:area] = area if area.present?



ActiveRecord::Base.transaction do
# 1) 文字・数値などを反映（空は反映しない）
shop.update!(attrs) if attrs.present?

# 2) 管理画面で選んだ写真だけ Shop にコピー（追記）
apply_selected_attachments!(@req, shop)

# 3) 承認
@req.update!(status: :approved)
end

redirect_to admin_shop_edit_requests_path(status: "pending"),
notice: "承認して反映しました"
rescue ActiveRecord::RecordInvalid => e
redirect_to admin_shop_edit_requests_path(status: "pending"),
alert: "反映に失敗しました：#{e.record.errors.full_messages.join(' / ')}"
end

def reject
@req.update!(status: :rejected)
redirect_to admin_shop_edit_requests_path(status: "pending"),
alert: "却下しました"
rescue ActiveRecord::RecordInvalid => e
redirect_to admin_shop_edit_requests_path(status: "pending"),
alert: "却下に失敗しました：#{e.record.errors.full_messages.join(' / ')}"
end

private

def set_req
@req = ShopEditRequest.includes(:shop).find(params[:id])
end

# ✅ 空欄は反映しない（変更された項目だけ反映）
def build_shop_attrs_from_request(req)
attrs = {}

name = req.proposed_name.to_s.strip
attrs[:name] = name if name.present?

address = req.proposed_address.to_s.strip
attrs[:address] = address if address.present?

station = req.proposed_nearest_station.to_s.strip
attrs[:nearest_station] = station if station.present?

phone = req.proposed_phone.to_s.strip
attrs[:phone] = phone if phone.present?

opening = req.proposed_opening_hours.to_s.strip
attrs[:opening_hours] = opening if opening.present?

# 日付（空なら反映しない）
attrs[:last_confirmed_on] = req.proposed_last_confirmed_on if req.proposed_last_confirmed_on.present?

# セレクト系（"0"/"1" で来ることがあるので変換）
smoking_area = req.proposed_smoking_area.to_s.strip
if smoking_area.present?
attrs[:smoking_area] = smoking_area.match?(/\A\d+\z/) ? smoking_area.to_i : smoking_area
end

smoking_type = req.proposed_smoking_type.to_s.strip
if smoking_type.present?
attrs[:smoking_type] = smoking_type.match?(/\A\d+\z/) ? smoking_type.to_i : smoking_type
end

# ジャンル（空なら反映しない）
genre = req.genre.to_s.strip
if genre.present?
attrs[:genre] = genre
if genre == "その他"
attrs[:genre_other] = req.genre_other.to_s.strip
else
attrs[:genre_other] = nil
end
end

# ✅ 編集依頼の「補足(note)」を店舗の note に反映（空欄は反映しない）
req_note = req.note.to_s.strip
attrs[:note] = req_note if req_note.present?

# ✅ サムネ（管理画面の approve フォームから入る値を優先）
tk = params.dig(:apply, :thumbnail_kind).to_s.strip
ti = params.dig(:apply, :thumbnail_index).to_s.strip

if tk.present?
attrs[:thumbnail_kind] = tk
else
proposed_tk = req.try(:proposed_thumbnail_kind).to_s.strip
attrs[:thumbnail_kind] = proposed_tk if proposed_tk.present?
end

if ti.present?
attrs[:thumbnail_index] = ti.to_i
else
proposed_ti = req.try(:proposed_thumbnail_index)
attrs[:thumbnail_index] = proposed_ti.to_i if proposed_ti.present?
end

attrs
end

# ✅ 管理画面で選ばれた blob だけ attach する（複製はしない）
def apply_selected_attachments!(req, shop)
apply = params[:apply] || {}

attach_by_blob_ids(req, shop, :food_photos, apply[:food_blob_ids])
attach_by_blob_ids(req, shop, :interior_photos, apply[:interior_blob_ids])
attach_by_blob_ids(req, shop, :exterior_photos, apply[:exterior_blob_ids])
attach_by_blob_ids(req, shop, :menu_photos, apply[:menu_blob_ids])
end

def attach_by_blob_ids(req, shop, name, blob_ids)
return unless req.respond_to?(name) && shop.respond_to?(name)

ids = Array(blob_ids).map { |v| v.to_s.strip }.reject(&:blank?).uniq
return if ids.empty?

# req に実際に付いている blob だけ許可（改ざん対策）
allowed = req.public_send(name).attachments.map { |a| a.blob_id.to_s }
ids &= allowed
return if ids.empty?

ActiveStorage::Blob.where(id: ids).find_each do |b|
shop.public_send(name).attach(b)
end
end
end