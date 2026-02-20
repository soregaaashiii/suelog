class AddGenreToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :genre, :string
    add_column :shops, :genre_other, :string
  end
end
