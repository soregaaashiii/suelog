class AddGurunaviCsvConfidence < ActiveRecord::Migration[8.1]
  def change
    add_column :gurunavi_csv_targets, :confidence, :integer, default: 0, null: false
    add_column :gurunavi_csv_matches, :confidence, :integer, default: 0, null: false
  end
end
