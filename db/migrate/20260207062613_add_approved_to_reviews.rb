class AddApprovedToReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :reviews, :approved, :boolean, null: false, default: false
    
  end
end
