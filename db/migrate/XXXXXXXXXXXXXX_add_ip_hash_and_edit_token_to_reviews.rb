class AddIpHashAndEditTokenToReviews < ActiveRecord::Migration[8.1]
def change
add_column :reviews, :ip_hash, :string
add_column :reviews, :edit_token, :string

add_index :reviews, :edit_token, unique: true
add_index :reviews, [:shop_id, :ip_hash], unique: true
end
end
