class MakeShopIdNullableOnPageViews < ActiveRecord::Migration[8.1]
  def change
    change_column_null :page_views, :shop_id, true
  end
end
