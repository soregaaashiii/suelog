class AddIpHashToReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :reviews, :ip_hash, :string
  end
end
