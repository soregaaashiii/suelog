# frozen_string_literal: true

class AddTocEnabledToArticles < ActiveRecord::Migration[7.0]
  def change
    add_column :articles, :toc_enabled, :boolean, null: false, default: false
  end
end