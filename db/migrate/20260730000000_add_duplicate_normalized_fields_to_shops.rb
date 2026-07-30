# frozen_string_literal: true

class AddDuplicateNormalizedFieldsToShops < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  class MigrationShop < ActiveRecord::Base
    self.table_name = "shops"
  end

  def up
    add_column :shops, :duplicate_normalized_name, :string unless column_exists?(:shops, :duplicate_normalized_name)
    add_column :shops, :duplicate_normalized_address, :string unless column_exists?(:shops, :duplicate_normalized_address)

    MigrationShop.reset_column_information
    MigrationShop.in_batches(of: 500) do |relation|
      rows = relation.pluck(:id, :name, :address).map do |id, name, address|
        {
          id:,
          duplicate_normalized_name: normalize_duplicate_text(name).presence,
          duplicate_normalized_address: normalize_duplicate_text(address).presence
        }
      end

      MigrationShop.upsert_all(
        rows,
        unique_by: :id,
        update_only: %i[duplicate_normalized_name duplicate_normalized_address],
        record_timestamps: false
      )
    end

    add_normalized_index(:duplicate_normalized_name)
    add_normalized_index(:duplicate_normalized_address)
  end

  def down
    remove_index :shops, :duplicate_normalized_address if index_exists?(:shops, :duplicate_normalized_address)
    remove_index :shops, :duplicate_normalized_name if index_exists?(:shops, :duplicate_normalized_name)
    remove_column :shops, :duplicate_normalized_address if column_exists?(:shops, :duplicate_normalized_address)
    remove_column :shops, :duplicate_normalized_name if column_exists?(:shops, :duplicate_normalized_name)
  end

  private

  def add_normalized_index(column)
    return if index_exists?(:shops, column)

    options = connection.adapter_name.match?(/postgres/i) ? { algorithm: :concurrently } : {}
    add_index :shops, column, **options
  end

  def normalize_duplicate_text(text)
    return "" if text.blank?

    text.to_s
        .tr("０-９Ａ-Ｚａ-ｚ", "0-9A-Za-z")
        .downcase
        .gsub(/[[:space:]]+/, "")
        .gsub(/[()（）\[\]【】「」『』・･,，.。\-ー−―]/, "")
        .strip
  end
end
