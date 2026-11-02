class AddGurunaviAffiliateFieldsToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :gurunavi_url, :text
    add_column :shops, :gurunavi_affiliate_url, :text
    add_column :shops, :hide_gurunavi_booking_button, :boolean, default: false, null: false
  end
end
