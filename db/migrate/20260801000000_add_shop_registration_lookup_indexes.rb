# frozen_string_literal: true

class AddShopRegistrationLookupIndexes < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  INDEXES = [
    [:shops, :normalized_phone, "index_shops_on_normalized_phone"],
    [:shops, %i[name address approved], "index_shops_on_name_address_approved"],
    [:shops, :address, "index_shops_on_address"],
    [:shops, :created_at, "index_shops_on_created_at"],
    [:shops, %i[approved rejected], "index_shops_on_approved_and_rejected"]
  ].freeze

  def up
    INDEXES.each do |table, columns, name|
      next if index_exists?(table, columns)

      options = connection.adapter_name.match?(/postgres/i) ? { algorithm: :concurrently } : {}
      add_index table, columns, name:, **options
    end
  end

  def down
    INDEXES.reverse_each do |table, _columns, name|
      next unless index_name_exists?(table, name)

      options = connection.adapter_name.match?(/postgres/i) ? { algorithm: :concurrently } : {}
      remove_index table, name:, **options
    end
  end
end
