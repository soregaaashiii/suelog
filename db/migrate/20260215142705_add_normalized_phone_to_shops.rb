class AddNormalizedPhoneToShops < ActiveRecord::Migration[7.1]
def change
add_column :shops, :normalized_phone, :string
add_index :shops, :normalized_phone, unique: true
end
end