# frozen_string_literal: true

class SearchConsolePageMetric < ApplicationRecord
  belongs_to :search_console_import
  enum :period, { current: 0, previous: 1 }, prefix: true
  validates :path, presence: true
  validates :clicks, :impressions, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
