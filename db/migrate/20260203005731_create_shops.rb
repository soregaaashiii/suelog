class CreateShops < ActiveRecord::Migration[8.1]
  def change
    create_table :shops do |t|
      t.string :name
      t.string :area
      t.text :note

      t.timestamps
    end
  end
end
