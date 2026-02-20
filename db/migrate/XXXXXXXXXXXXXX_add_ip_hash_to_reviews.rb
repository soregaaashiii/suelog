
# db/migrate/XXXXXXXXXXXXXX_add_ip_hash_to_reviews.rb
class AddIpHashToReviews < ActiveRecord::Migration[8.1]
def change
add_column :reviews, :ip_hash, :string
add_index :reviews, [:shop_id, :ip_hash], unique: true
end
end