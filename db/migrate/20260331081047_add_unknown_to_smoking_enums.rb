# frozen_string_literal: true

class AddUnknownToSmokingEnums < ActiveRecord::Migration[8.1]
def up
# 既存データでNULLや空の場合は unknown に寄せる（安全処理）
execute <<~SQL
UPDATE shops
SET smoking_area = 2
WHERE smoking_area IS NULL;
SQL

execute <<~SQL
UPDATE shops
SET smoking_type = 3
WHERE smoking_type IS NULL;
SQL
end

def down
# 元に戻す（unknown → NULL）
execute <<~SQL
UPDATE shops
SET smoking_area = NULL
WHERE smoking_area = 2;
SQL

execute <<~SQL
UPDATE shops
SET smoking_type = NULL
WHERE smoking_type = 3;
SQL
end
end