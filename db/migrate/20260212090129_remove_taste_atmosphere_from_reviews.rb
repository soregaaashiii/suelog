class RemoveTasteAtmosphereFromReviews < ActiveRecord::Migration[7.0]
def up
remove_column :reviews, :taste if column_exists?(:reviews, :taste)
remove_column :reviews, :atmosphere if column_exists?(:reviews, :atmosphere)
end

def down
add_column :reviews, :taste, :integer
add_column :reviews, :atmosphere, :integer
end
end