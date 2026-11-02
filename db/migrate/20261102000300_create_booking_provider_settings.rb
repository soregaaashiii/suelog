class CreateBookingProviderSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :booking_provider_settings do |t|
      t.string :provider, null: false
      t.boolean :hidden, null: false, default: false
      t.timestamps
    end
    add_index :booking_provider_settings, :provider, unique: true
  end
end
