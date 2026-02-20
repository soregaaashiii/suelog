class AddStatusToReviews < ActiveRecord::Migration[8.1]
  def change
  add_column :reviews, :status, :integer, default: 0, null: false
end

end
