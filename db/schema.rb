# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_31_173641) do
  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "affiliate_ads", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "image_path"
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["key"], name: "index_affiliate_ads_on_key", unique: true
  end

  create_table "articles", force: :cascade do |t|
    t.text "admin_note"
    t.text "content"
    t.datetime "created_at", null: false
    t.text "meta_description"
    t.boolean "published"
    t.datetime "published_at"
    t.text "recommended_areas", default: "", null: false
    t.integer "recommended_order", default: 0, null: false
    t.string "seo_title"
    t.string "slug"
    t.text "summary"
    t.string "title"
    t.datetime "updated_at", null: false
  end

  create_table "contact_messages", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name", null: false
    t.string "subject", null: false
    t.datetime "updated_at", null: false
  end

  create_table "page_views", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_hash"
    t.boolean "is_bot"
    t.string "path"
    t.text "referrer"
    t.integer "shop_id"
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.string "utm_campaign"
    t.string "utm_medium"
    t.string "utm_source"
    t.index ["shop_id"], name: "index_page_views_on_shop_id"
  end

  create_table "review_reports", force: :cascade do |t|
    t.text "comment"
    t.datetime "created_at", null: false
    t.string "reason"
    t.string "reporter_name"
    t.integer "review_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["review_id"], name: "index_review_reports_on_review_id"
  end

  create_table "reviews", force: :cascade do |t|
    t.boolean "approved"
    t.string "author_name"
    t.text "comment"
    t.datetime "created_at", null: false
    t.string "edit_token"
    t.string "ip_hash"
    t.integer "rating"
    t.integer "shop_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["edit_token"], name: "index_reviews_on_edit_token", unique: true
    t.index ["shop_id"], name: "index_reviews_on_shop_id"
  end

  create_table "shop_clicks", force: :cascade do |t|
    t.integer "article_id"
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.integer "shop_id", null: false
    t.datetime "updated_at", null: false
    t.index ["article_id", "shop_id", "kind"], name: "index_shop_clicks_on_article_id_and_shop_id_and_kind"
    t.index ["article_id"], name: "index_shop_clicks_on_article_id"
    t.index ["created_at"], name: "index_shop_clicks_on_created_at"
    t.index ["kind"], name: "index_shop_clicks_on_kind"
    t.index ["shop_id"], name: "index_shop_clicks_on_shop_id"
  end

  create_table "shop_edit_requests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "genre"
    t.string "genre_other"
    t.text "note"
    t.string "proposed_address"
    t.string "proposed_area"
    t.string "proposed_closed_days_text"
    t.text "proposed_holiday_hours_text"
    t.date "proposed_last_confirmed_on"
    t.string "proposed_name"
    t.string "proposed_nearest_station"
    t.text "proposed_opening_hours"
    t.json "proposed_opening_hours_json", default: {}, null: false
    t.text "proposed_opening_hours_text"
    t.string "proposed_phone"
    t.text "proposed_public_store_details"
    t.integer "proposed_smoking_area"
    t.integer "proposed_smoking_type"
    t.text "proposed_special_hours_note"
    t.integer "proposed_thumbnail_index"
    t.string "proposed_thumbnail_kind"
    t.string "proposer_name"
    t.integer "shop_id", null: false
    t.integer "status", default: 0, null: false
    t.text "status_report_note"
    t.string "status_report_type"
    t.datetime "updated_at", null: false
    t.index ["proposed_opening_hours_json"], name: "index_shop_edit_requests_on_proposed_opening_hours_json"
    t.index ["shop_id"], name: "index_shop_edit_requests_on_shop_id"
    t.index ["status_report_type"], name: "index_shop_edit_requests_on_status_report_type"
  end

  create_table "shop_reports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "detail"
    t.string "reason"
    t.string "reporter_name"
    t.integer "shop_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id"], name: "index_shop_reports_on_shop_id"
  end

  create_table "shop_verification_submissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "memo"
    t.string "result", null: false
    t.datetime "reviewed_at"
    t.bigint "reviewed_by_id"
    t.integer "shop_id", null: false
    t.string "smoking_location"
    t.string "status", default: "pending", null: false
    t.integer "sub_admin_user_id", null: false
    t.string "tobacco_type"
    t.datetime "updated_at", null: false
    t.index ["reviewed_by_id"], name: "index_shop_verification_submissions_on_reviewed_by_id"
    t.index ["shop_id"], name: "index_shop_verification_submissions_on_shop_id"
    t.index ["smoking_location"], name: "index_shop_verification_submissions_on_smoking_location"
    t.index ["status"], name: "index_shop_verification_submissions_on_status"
    t.index ["sub_admin_user_id"], name: "index_shop_verification_submissions_on_sub_admin_user_id"
    t.index ["tobacco_type"], name: "index_shop_verification_submissions_on_tobacco_type"
  end

  create_table "shops", force: :cascade do |t|
    t.string "address"
    t.integer "all_you_can_drink_type", default: 0, null: false
    t.boolean "approved", default: false, null: false
    t.string "area"
    t.integer "atmosphere"
    t.string "budget_range"
    t.string "closed_days_text"
    t.datetime "created_at", null: false
    t.string "custom_affiliate_label"
    t.string "custom_affiliate_url"
    t.string "genre"
    t.string "genre_other"
    t.datetime "held_at"
    t.text "hold_note"
    t.string "hold_reason"
    t.text "holiday_hours_text"
    t.string "hotpepper_url"
    t.json "import_metadata", default: {}, null: false
    t.string "import_source"
    t.datetime "imported_at"
    t.date "last_confirmed_on"
    t.string "last_order_text"
    t.float "latitude"
    t.float "longitude"
    t.string "name"
    t.string "nearest_station"
    t.string "normalized_phone"
    t.text "note"
    t.boolean "on_hold", default: false, null: false
    t.text "opening_hours"
    t.json "opening_hours_json"
    t.text "opening_hours_text"
    t.string "phone"
    t.boolean "phone_check_on_hold", default: false, null: false
    t.string "place_id"
    t.integer "private_room_type", default: 0, null: false
    t.text "public_store_details"
    t.text "raw_import_text"
    t.boolean "rejected"
    t.json "seat_type_tags", default: [], null: false
    t.integer "smoking_area"
    t.string "smoking_hours_text"
    t.integer "smoking_type"
    t.boolean "smoking_unverified", default: false, null: false
    t.string "source"
    t.text "special_hours_note"
    t.string "tabelog_affiliate_url"
    t.string "tabelog_candidate_affiliate_url"
    t.datetime "tabelog_candidate_matched_at"
    t.string "tabelog_candidate_method"
    t.string "tabelog_candidate_url"
    t.string "tabelog_match_method"
    t.datetime "tabelog_matched_at"
    t.string "tabelog_url"
    t.integer "taste"
    t.integer "thumbnail_index"
    t.string "thumbnail_kind"
    t.datetime "updated_at", null: false
    t.index ["hold_reason"], name: "index_shops_on_hold_reason"
    t.index ["on_hold"], name: "index_shops_on_on_hold"
    t.index ["phone_check_on_hold"], name: "index_shops_on_phone_check_on_hold"
    t.index ["place_id"], name: "index_shops_on_place_id", unique: true
    t.index ["source"], name: "index_shops_on_source"
  end

  create_table "sub_admin_users", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "last_login_at"
    t.string "login_id", null: false
    t.text "memo"
    t.string "name", null: false
    t.string "password_digest", null: false
    t.json "permissions", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["login_id"], name: "index_sub_admin_users_on_login_id", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "page_views", "shops"
  add_foreign_key "review_reports", "reviews"
  add_foreign_key "reviews", "shops"
  add_foreign_key "shop_clicks", "articles"
  add_foreign_key "shop_clicks", "shops"
  add_foreign_key "shop_edit_requests", "shops"
  add_foreign_key "shop_reports", "shops"
  add_foreign_key "shop_verification_submissions", "shops"
  add_foreign_key "shop_verification_submissions", "sub_admin_users"
end
