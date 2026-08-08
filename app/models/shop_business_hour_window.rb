# frozen_string_literal: true

class ShopBusinessHourWindow < ApplicationRecord
  belongs_to :shop

  validates :weekday, inclusion: { in: 0..6 }
  validates :opens_at_minute, :closes_at_minute,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 1440 }
  validate :closes_after_open

  private

  def closes_after_open
    return if opens_at_minute.blank? || closes_at_minute.blank?
    return if closes_at_minute > opens_at_minute

    errors.add(:closes_at_minute, "must be after opens_at_minute")
  end
end
