class AddRatingToReviews < ActiveRecord::Migration[8.1]
def up
# rating 追加（1〜5前提・NULL不可・デフォルト3）
add_column :reviews, :rating, :integer, null: false, default: 3

# 既存データがある場合の移行（taste/atmosphereが残っている場合のみ）
if column_exists?(:reviews, :taste) && column_exists?(:reviews, :atmosphere)
execute <<~SQL
UPDATE reviews
SET rating = ROUND((COALESCE(taste, 3) + COALESCE(atmosphere, 3)) / 2.0)
SQL
end
end

def down
remove_column :reviews, :rating
end
end