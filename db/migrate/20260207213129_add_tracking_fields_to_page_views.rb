class AddTrackingFieldsToPageViews < ActiveRecord::Migration[8.1]
  def change
    add_column :page_views, :ip_hash, :string
    add_column :page_views, :user_agent, :text
    add_column :page_views, :referrer, :text
    add_column :page_views, :utm_source, :string
    add_column :page_views, :utm_medium, :string
    add_column :page_views, :utm_campaign, :string
    add_column :page_views, :is_bot, :boolean
  end
end
