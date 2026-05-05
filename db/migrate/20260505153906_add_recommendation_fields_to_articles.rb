# frozen_string_literal: true

class AddRecommendationFieldsToArticles < ActiveRecord::Migration[8.1]
  def change
    add_column :articles, :recommended_areas, :text, default: "", null: false
    add_column :articles, :recommended_order, :integer, default: 0, null: false
  end
end