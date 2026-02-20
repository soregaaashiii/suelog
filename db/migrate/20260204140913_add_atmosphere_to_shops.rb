class AddAtmosphereToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :atmosphere, :integer
  end
end
