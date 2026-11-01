class AddHotpepperAffiliateUrlToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :hotpepper_affiliate_url, :text
  end
end
