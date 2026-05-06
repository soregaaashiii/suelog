class AddArticleToShopClicks < ActiveRecord::Migration[8.1]
  def change
    add_reference :shop_clicks, :article, null: true, foreign_key: true
    add_index :shop_clicks, [:article_id, :shop_id, :kind]
  end
end