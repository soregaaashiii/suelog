# frozen_string_literal: true

class Admin::ShopEditRequestsController < Admin::BaseController
before_action :set_req, only: [:show, :approve, :reject]

def index
@status = params[:status].presence || "pending"

scope = ShopEditRequest
.includes(
:shop,
food_photos_attachments: :blob,
interior_photos_attachments: :blob,
exterior_photos_attachments: :blob,
menu_photos_attachments: :blob
)
.order(created_at: :desc)

scope =
case @status
when "pending"
scope.where(status: :pending)
when "approved"
scope.where(status: :approved)
when "rejected"
scope.where(status: :rejected)
when "all"
scope
else
scope.where(status: :pending)
end

@edit_requests = scope
@requests = scope
end

def show
@shop = @req.shop
end

def approve
shop = @req.shop
attrs = build_shop_attrs_from_request(@req)

area = safe_str(@req.proposed_area)
attrs[:area] = area if area.present?

if attrs[:last_confirmed_on].present?
attrs[:smoking_unverified] = false
end

ActiveRecord::Base.transaction do
shop.update!(attrs) if attrs.present?
apply_selected_attachments!(@req, shop)
apply_thumbnail_if_present!(shop)
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

def build_shop_attrs_from_request(req)
attrs = {}

name = safe_str(req.proposed_name)
attrs[:name] = name if name.present?

address = safe_str(req.proposed_address)
attrs[:address] = address if address.present?

station = safe_str(req.proposed_nearest_station)
attrs[:nearest_station] = station if station.present?

phone = safe_str(req.proposed_phone)
attrs[:phone] = phone if phone.present?

opening_hours_text =
if req.respond_to?(:proposed_opening_hours_text)
safe_str(req.proposed_opening_hours_text)
elsif req.respond_to?(:opening_hours_text)
safe_str(req.opening_hours_text)
else
""
end
attrs[:opening_hours_text] = opening_hours_text if opening_hours_text.present?

holiday_hours_text =
if req.respond_to?(:proposed_holiday_hours_text)
safe_str(req.proposed_holiday_hours_text)
elsif req.respond_to?(:holiday_hours_text)
safe_str(req.holiday_hours_text)
else
""
end
attrs[:holiday_hours_text] = holiday_hours_text if holiday_hours_text.present?

closed_days_text =
if req.respond_to?(:proposed_closed_days_text)
safe_str(req.proposed_closed_days_text)
elsif req.respond_to?(:closed_days_text)
safe_str(req.closed_days_text)
else
""
end
attrs[:closed_days_text] = closed_days_text if closed_days_text.present?

if req.respond_to?(:proposed_opening_hours_json) &&
req.proposed_opening_hours_json.present? &&
req.proposed_opening_hours_json.to_h.any?
attrs[:opening_hours_json] = req.proposed_opening_hours_json
end

attrs[:last_confirmed_on] = req.proposed_last_confirmed_on if req.proposed_last_confirmed_on.present?

smoking_area =
case safe_str(req.proposed_smoking_area)
when "area_separated", "proposed_area_separated"
"separated"
when "area_all_smoking", "proposed_area_all_smoking"
"all_smoking"
when "area_unknown", "proposed_area_unknown"
"unknown"
else
""
end
attrs[:smoking_area] = smoking_area if smoking_area.present?

smoking_type =
case safe_str(req.proposed_smoking_type)
when "type_both_ok", "proposed_type_both_ok"
"both_ok"
when "type_electronic_only", "proposed_type_electronic_only"
"electronic_only"
when "type_paper_only", "proposed_type_paper_only"
"paper_only"
when "type_unknown", "proposed_type_unknown"
"unknown"
else
""
end
attrs[:smoking_type] = smoking_type if smoking_type.present?

genre = safe_str(req.genre)
if genre.present?
attrs[:genre] = genre
attrs[:genre_other] = (genre == "その他" ? safe_str(req.genre_other) : nil)
end

req_note = safe_str(req.note)
attrs[:note] = req_note if req_note.present?

attrs
end

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

allowed = req.public_send(name).attachments.map { |a| a.blob_id.to_s }
ids &= allowed
return if ids.empty?

ActiveStorage::Blob.where(id: ids).find_each do |blob|
shop.public_send(name).attach(blob)
end
end

def apply_thumbnail_if_present!(shop)
return unless shop.respond_to?(:thumbnail_kind=) || shop.respond_to?(:thumbnail_index=)

apply = params[:apply] || {}

thumbnail_kind = safe_str(apply[:thumbnail_kind])
thumbnail_index = safe_str(apply[:thumbnail_index])

if thumbnail_kind.blank? && @req.respond_to?(:proposed_thumbnail_kind)
thumbnail_kind = safe_str(@req.proposed_thumbnail_kind)
end

if thumbnail_index.blank? && @req.respond_to?(:proposed_thumbnail_index) && @req.proposed_thumbnail_index.present?
thumbnail_index = @req.proposed_thumbnail_index.to_i.to_s
end

updates = {}
updates[:thumbnail_kind] = thumbnail_kind if thumbnail_kind.present? && shop.respond_to?(:thumbnail_kind=)
updates[:thumbnail_index] = thumbnail_index.to_i if thumbnail_index.present? && shop.respond_to?(:thumbnail_index=)

shop.update!(updates) if updates.present?
end

def safe_str(value)
value.to_s.strip
end
end