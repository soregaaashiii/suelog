class CreateReviewReports < ActiveRecord::Migration[8.1]
  def change
    create_table :review_reports do |t|
      t.references :review, null: false, foreign_key: true
      t.string :reporter_name
      t.string :reason
      t.text :comment
      t.integer :status, null: false, default: 0

      t.timestamps
    end
  end
end
