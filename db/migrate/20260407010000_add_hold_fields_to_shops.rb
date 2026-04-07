# frozen_string_literal: true

class AddHoldFieldsToShops < ActiveRecord::Migration[8.0]
  def change
    add_column :shops, :on_hold, :boolean, null: false, default: false
    add_column :shops, :hold_reason, :string
    add_column :shops, :hold_note, :text
    add_column :shops, :held_at, :datetime

    add_index :shops, :on_hold
    add_index :shops, :hold_reason
  end
end