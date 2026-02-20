class AddAddressToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :address, :string
  end
end
