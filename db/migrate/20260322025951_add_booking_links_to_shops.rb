class AddBookingLinksToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :tabelog_url, :string
    add_column :shops, :hotpepper_url, :string
  end
end
