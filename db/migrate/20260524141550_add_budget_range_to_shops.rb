class AddBudgetRangeToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :budget_range, :string
  end
end
