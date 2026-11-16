require "test_helper"

class ShopOpeningStatusTest < ActiveSupport::TestCase
  test "deduplicates identical schedules while preserving midnight breaks and missing hours" do
    schedules = [
      { "opening_hours_json" => {}, "opening_hours_text" => "月 11:30-15:00, 17:00-23:30" },
      { "opening_hours_json" => {}, "opening_hours_text" => "月 17:00-02:00" },
      { "opening_hours_json" => { "monday" => { "open" => "11:30", "close" => "23:30", "break_enabled" => true, "break_start" => "15:00", "break_end" => "17:00" } } },
      { "opening_hours_json" => { "monday" => { "closed" => true } } },
      { "opening_hours_json" => {}, "holiday_hours_text" => "12:00-18:00" },
      { "opening_hours_json" => {} }
    ]
    %w[01:00 11:29 11:30 14:59 15:00 16:59 17:00 23:30].each do |clock|
      travel_to Time.zone.parse("2026-11-16 #{clock}") do
        evaluator = ShopOpeningStatus.new
        schedules.each do |attributes|
          row = ShopOpeningStatus::COLUMNS.index_with { |key| attributes[key] }
          shop = Shop.instantiate(row)
          3.times { assert_equal shop.open_now?, evaluator.for_row(row) }
          3.times { assert_equal shop.open_now?, evaluator.for_shop(shop) }
        end
        assert_equal schedules.size, evaluator.instance_variable_get(:@statuses).size
      end
    end
  end

  test "request scopes do not keep an opening status after data or time changes" do
    shop = Shop.new(opening_hours_text: "月 11:00-15:00")
    travel_to Time.zone.parse("2026-11-16 14:59") do
      assert ShopOpeningStatus.new.for_shop(shop)
      shop.opening_hours_text = "月 17:00-23:00"
      refute ShopOpeningStatus.new.for_shop(shop)
    end
    shop.opening_hours_text = "月 11:00-15:00"
    travel_to(Time.zone.parse("2026-11-16 15:00")) { refute ShopOpeningStatus.new.for_shop(shop) }
  end
end
