class CreatePageViews < ActiveRecord::Migration[8.1]
  def change
    create_table :page_views do |t|
      t.references :shop, null: false, foreign_key: true
      t.string :path

      t.timestamps
    end
  end
end
