class CreateSearchConsoleImports < ActiveRecord::Migration[8.1]
  def change
    create_table :search_console_imports do |t|
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.date :previous_start
      t.date :previous_end
      t.string :current_filename, null: false
      t.string :previous_filename
      t.text :search_context, null: false
      t.json :statistics, default: {}, null: false
      t.timestamps
    end

    create_table :search_console_page_metrics do |t|
      t.references :search_console_import, null: false, foreign_key: true
      t.integer :period, null: false
      t.string :path, limit: 512, null: false
      t.bigint :clicks, null: false
      t.bigint :impressions, null: false
      t.decimal :position, precision: 12, scale: 4
      t.timestamps
    end
    add_index :search_console_page_metrics, [:search_console_import_id, :period, :path], unique: true, name: "index_search_console_metrics_on_import_period_path"
  end
end
