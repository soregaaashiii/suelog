# /Users/kawamuratakuya/dev/suelog/db/migrate/xxxxxx_create_affiliate_ads.rb
class CreateAffiliateAds < ActiveRecord::Migration[7.1]
  def change
    create_table :affiliate_ads do |t|
      t.string :key, null: false
      t.string :url, null: false
      t.string :image_path
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :affiliate_ads, :key, unique: true
  end
end
