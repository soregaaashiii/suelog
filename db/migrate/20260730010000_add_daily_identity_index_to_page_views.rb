# frozen_string_literal: true

class AddDailyIdentityIndexToPageViews < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEX_NAME = "index_page_views_on_daily_identity_without_shop"

  def up
    return if index_exists?(:page_views, %i[path ip_hash created_at], name: INDEX_NAME)

    options = connection.adapter_name.match?(/postgres/i) ? { algorithm: :concurrently } : {}
    add_index :page_views,
              %i[path ip_hash created_at],
              name: INDEX_NAME,
              where: "shop_id IS NULL",
              **options
  end

  def down
    return unless index_exists?(:page_views, name: INDEX_NAME)

    options = connection.adapter_name.match?(/postgres/i) ? { algorithm: :concurrently } : {}
    remove_index :page_views, name: INDEX_NAME, **options
  end
end
