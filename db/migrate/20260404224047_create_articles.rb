class CreateArticles < ActiveRecord::Migration[8.1]
  def change
    create_table :articles do |t|
      t.string :title
      t.string :slug
      t.text :summary
      t.boolean :published
      t.datetime :published_at
      t.text :admin_note
      t.string :seo_title
      t.text :meta_description

      t.timestamps
    end
  end
end
