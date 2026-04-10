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

ActiveRecord::Schema[8.1].define(version: 2026_04_10_033311) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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

  create_table "articles", force: :cascade do |t|
    t.text "admin_note"
    t.datetime "created_at", null: false
    t.text "meta_description"
    t.boolean "published"
    t.datetime "published_at"
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

