class CreateSeoPageTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :seo_page_tasks do |t|
      t.string :path, limit: 512, null: false
      t.string :status, null: false, default: "pending"
      t.text :note
      t.date :handled_on
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :seo_page_tasks, :path, unique: true
  end
end
