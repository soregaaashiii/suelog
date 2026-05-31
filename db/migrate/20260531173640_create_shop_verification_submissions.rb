class CreateShopVerificationSubmissions < ActiveRecord::Migration[7.0]
  def change
    create_table :shop_verification_submissions do |t|
      t.references :shop, null: false, foreign_key: true
      t.references :sub_admin_user, null: false, foreign_key: true

      t.string :result, null: false
      t.text :memo
      t.string :status, null: false, default: "pending"

      t.bigint :reviewed_by_id
      t.datetime :reviewed_at

      t.timestamps
    end

    add_index :shop_verification_submissions, :status
    add_index :shop_verification_submissions, :reviewed_by_id
  end
end
