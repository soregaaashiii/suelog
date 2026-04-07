# frozen_string_literal: true

class AddStatusReportFieldsToShopEditRequests < ActiveRecord::Migration[8.0]
  def change
    add_column :shop_edit_requests, :status_report_type, :string
    add_column :shop_edit_requests, :status_report_note, :text

    add_index :shop_edit_requests, :status_report_type
  end
end