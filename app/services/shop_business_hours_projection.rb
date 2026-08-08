# frozen_string_literal: true

class ShopBusinessHoursProjection
  WEEKDAY_KEYS = %w[sunday monday tuesday wednesday thursday friday saturday].freeze
  WEEKDAY_LABELS = %w[日 月 火 水 木 金 土].freeze

  class << self
    def rows_for(shop)
      WEEKDAY_KEYS.each_with_index.flat_map do |day_key, weekday|
        intervals_for_day(shop, day_key:, weekday:).map do |opens_at_minute, closes_at_minute|
          {
            shop_id: shop.id,
            weekday:,
            opens_at_minute:,
            closes_at_minute:
          }
        end
      end
    end

    def sync!(shop)
      rows = rows_for(shop)

      ShopBusinessHourWindow.transaction(requires_new: true) do
        ShopBusinessHourWindow.where(shop_id: shop.id).delete_all
        ShopBusinessHourWindow.insert_all!(rows) if rows.any?
      end
    end

    def rebuild!(scope: Shop.all, batch_size: 200)
      scope.select(:id, :opening_hours_json, :opening_hours_text, :holiday_hours_text)
           .in_batches(of: batch_size) do |batch|
        shops = batch.to_a
        rows = shops.flat_map { |shop| rows_for(shop) }
        shop_ids = shops.map(&:id)

        ShopBusinessHourWindow.transaction(requires_new: true) do
          ShopBusinessHourWindow.where(shop_id: shop_ids).delete_all
          ShopBusinessHourWindow.insert_all!(rows) if rows.any?
        end

        yield shops.size, rows.size if block_given?
      end
    end

    def open_at?(shop, time)
      minute = time.hour * 60 + time.min
      rows_for(shop).any? do |row|
        row[:weekday] == time.wday &&
          row[:opens_at_minute] <= minute &&
          row[:closes_at_minute] > minute
      end
    end

    private

    def intervals_for_day(shop, day_key:, weekday:)
      holiday_ranges = shop.send(:time_ranges_from_text, shop.holiday_hours_text)
      return merge_intervals(holiday_ranges.flat_map { |range| interval_segments(*range) }) if holiday_ranges.present?

      day = shop.opening_hours_data[day_key]
      if day.present?
        return [] if shop.send(:truthy?, day["closed"])

        opens_at = shop.send(:hhmm_to_min, day["open"])
        closes_at = shop.send(:hhmm_to_min, day["close"])
        return [] if opens_at.nil? || closes_at.nil?

        intervals = interval_segments(opens_at, closes_at)
        if shop.send(:truthy?, day["break_enabled"])
          break_start = shop.send(:hhmm_to_min, day["break_start"])
          break_end = shop.send(:hhmm_to_min, day["break_end"])
          if break_start && break_end
            intervals = subtract_intervals(intervals, interval_segments(break_start, break_end))
          end
        end
        return merge_intervals(intervals)
      end

      ranges = shop.send(:time_ranges_from_text, shop.opening_hours_text, WEEKDAY_LABELS.fetch(weekday))
      merge_intervals(ranges.flat_map { |range| interval_segments(*range) })
    end

    def interval_segments(opens_at, closes_at)
      return [ [ 0, 1440 ] ] if opens_at.zero? && closes_at == 1440
      return opens_at < 1440 ? [ [ opens_at, 1440 ] ] : [] if closes_at == 1440
      return [ [ opens_at, closes_at ] ] if closes_at > opens_at

      segments = []
      segments << [ opens_at, 1440 ] if opens_at < 1440
      segments << [ 0, closes_at ] if closes_at.positive?
      merge_intervals(segments)
    end

    def subtract_intervals(intervals, exclusions)
      exclusions.reduce(intervals) do |remaining, (excluded_start, excluded_end)|
        remaining.flat_map do |start_minute, end_minute|
          if excluded_end <= start_minute || excluded_start >= end_minute
            [ [ start_minute, end_minute ] ]
          else
            parts = []
            parts << [ start_minute, excluded_start ] if excluded_start > start_minute
            parts << [ excluded_end, end_minute ] if excluded_end < end_minute
            parts
          end
        end
      end
    end

    def merge_intervals(intervals)
      intervals
        .reject { |start_minute, end_minute| end_minute <= start_minute }
        .sort_by(&:first)
        .each_with_object([]) do |(start_minute, end_minute), merged|
          if merged.empty? || start_minute > merged.last.last
            merged << [ start_minute, end_minute ]
          else
            merged.last[1] = [ merged.last.last, end_minute ].max
          end
        end
    end
  end
end
