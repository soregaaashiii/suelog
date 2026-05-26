class AddShopDetailImportFieldsToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :budget_range, :string
    add_column :shops, :last_order_text, :string

    add_column :shops,
                :private_room_type,
                :integer,
                default: 0,
                null: false

    add_column :shops,
                :seat_type_tags,
                :jsonb,
                default: [],
                null: false

    add_column :shops,
                :all_you_can_drink_type,
                :integer,
                default: 0,
                null: false

    add_column :shops, :raw_import_text, :text

    add_column :shops,
                :import_metadata,
                :jsonb,
                default: {},
                null: false

    add_column :shops, :import_source, :string
    add_column :shops, :imported_at, :datetime
  end
end