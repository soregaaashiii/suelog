class CreateSeoPageSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :seo_page_settings do |t|
      t.string :path, limit: 512, null: false
      t.string :title, limit: 200
      t.text :description
      t.integer :lock_version, default: 0, null: false
      t.timestamps
    end
    add_index :seo_page_settings, :path, unique: true

    create_table :seo_page_revisions do |t|
      t.references :seo_page_setting, null: false, foreign_key: true
      t.json :before_values, null: false, default: {}
      t.json :after_values, null: false, default: {}
      t.text :change_note
      t.timestamps
    end
    add_index :seo_page_revisions, [:seo_page_setting_id, :id]
  end
end
