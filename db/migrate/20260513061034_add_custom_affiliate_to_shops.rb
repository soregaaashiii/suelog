class AddCustomAffiliateToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :custom_affiliate_url, :string
    add_column :shops, :custom_affiliate_label, :string
  end
end