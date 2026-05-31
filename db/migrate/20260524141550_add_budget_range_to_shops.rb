class AddBudgetRangeToShops < ActiveRecord::Migration[8.1]
  def change
    return if column_exists?(:shops, :budget_range)

    add_column :shops, :budget_range, :string
  end
end
