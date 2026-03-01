
# frozen_string_literal: true

class AddProposedOpeningHoursJsonToShopEditRequests < ActiveRecord::Migration[8.0]
def change
# 編集依頼側に構造化営業時間を持たせる
# jsonb が使える前提（PostgreSQL）
add_column :shop_edit_requests, :proposed_opening_hours_json, :jsonb, null: false, default: {}
add_index :shop_edit_requests, :proposed_opening_hours_json, using: :gin
end
end