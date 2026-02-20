class AddEditTokenToReviews < ActiveRecord::Migration[7.1]
def change
add_column :reviews, :edit_token, :string
add_index :reviews, :edit_token, unique: true
end
end