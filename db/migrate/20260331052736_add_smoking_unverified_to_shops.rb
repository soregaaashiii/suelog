
# frozen_string_literal: true

class AddSmokingUnverifiedToShops < ActiveRecord::Migration[8.1]
def change
add_column :shops, :smoking_unverified, :boolean, default: false, null: false
end
end