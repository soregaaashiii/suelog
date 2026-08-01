# frozen_string_literal: true

class CoverShopRegistrationDuplicateCandidates < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  OLD_INDEX = "index_shops_on_created_at"
  NEW_INDEX = "index_shops_on_registration_duplicate_candidates"
  COLUMNS = %i[
    created_at
    id
    duplicate_normalized_name
    duplicate_normalized_address
  ].freeze

  def up
    options = connection.adapter_name.match?(/postgres/i) ? { algorithm: :concurrently } : {}

    add_index :shops, COLUMNS, name: NEW_INDEX, **options unless index_name_exists?(:shops, NEW_INDEX)
    remove_index :shops, name: OLD_INDEX, **options if index_name_exists?(:shops, OLD_INDEX)
  end

  def down
    options = connection.adapter_name.match?(/postgres/i) ? { algorithm: :concurrently } : {}

    add_index :shops, :created_at, name: OLD_INDEX, **options unless index_name_exists?(:shops, OLD_INDEX)
    remove_index :shops, name: NEW_INDEX, **options if index_name_exists?(:shops, NEW_INDEX)
  end
end
