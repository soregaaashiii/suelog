class CreateSubAdminUsers < ActiveRecord::Migration[7.0]
  def change
    create_table :sub_admin_users do |t|
      t.string :name, null: false
      t.string :login_id, null: false
      t.string :password_digest, null: false
      t.boolean :active, null: false, default: true
      t.json :permissions, null: false, default: []
      t.datetime :last_login_at
      t.text :memo

      t.timestamps
    end

    add_index :sub_admin_users, :login_id, unique: true
  end
end