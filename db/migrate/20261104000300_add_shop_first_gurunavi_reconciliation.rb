class AddShopFirstGurunaviReconciliation < ActiveRecord::Migration[8.1]
  def change
    add_column :gurunavi_csv_batches, :matching_basis, :string, null: false, default: "csv"
    create_table :gurunavi_csv_targets do |t|
      t.references :gurunavi_csv_batch, null: false, foreign_key: true
      t.bigint :shop_id, null: false
      t.text :shop_snapshot
      t.string :classification, null: false, default: "pending"
      t.string :state, null: false, default: "pending"
      t.text :reason
      t.bigint :selected_match_id
      t.timestamps
    end
    add_index :gurunavi_csv_targets, [ :gurunavi_csv_batch_id, :shop_id ], unique: true, name: "index_gcsv_target_shop"
    add_index :gurunavi_csv_targets, [ :gurunavi_csv_batch_id, :classification ], name: "index_gcsv_target_class"
    add_reference :gurunavi_csv_matches, :gurunavi_csv_target, foreign_key: true
  end
end
