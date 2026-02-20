class CreateReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :reviews do |t|
      t.references :shop, null: false, foreign_key: true
      t.integer :taste
      t.integer :atmosphere
      t.text :comment
      t.string :author_name

      t.timestamps
    end
  end
end
