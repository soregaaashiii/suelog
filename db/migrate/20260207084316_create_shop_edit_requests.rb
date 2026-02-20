class CreateShopEditRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :shop_edit_requests do |t|
      t.references :shop, null: false, foreign_key: true
      t.string :proposer_name
      t.text :note
      t.string :proposed_name
      t.string :proposed_address
      t.date :proposed_last_confirmed_on
      t.integer :status, null: false, default: 0
      t.timestamps
    end
  end
end
