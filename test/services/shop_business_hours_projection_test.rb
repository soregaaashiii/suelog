require "test_helper"

class ShopBusinessHoursProjectionTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  MONDAY = Date.new(2026, 8, 3)
  TUESDAY = MONDAY + 1.day

  test "normal opening boundaries match the legacy predicate" do
    shop = shop_with_json("monday" => day(open: "09:00", close: "18:00"))

    assert_matches_legacy shop, MONDAY, %w[08:59 09:00 12:00 17:59 18:00 18:01]
  end

  test "overnight boundaries and the legacy current-weekday behavior match" do
    shop = shop_with_json(
      "monday" => day(open: "18:00", close: "02:00"),
      "tuesday" => { "closed" => true }
    )

    assert_matches_legacy shop, MONDAY, %w[01:59 02:00 02:01 17:59 18:00 23:59]
    assert_matches_legacy shop, TUESDAY, %w[00:00 01:59 02:00]
  end

  test "all-day equal endpoints and 24:00 match legacy behavior" do
    all_day = shop_with_json("monday" => day(open: "00:00", close: "24:00"))
    equal = shop_with_json("monday" => day(open: "09:00", close: "09:00"))
    end_of_day = shop_with_json("monday" => day(open: "24:00", close: "24:00"))

    %w[00:00 05:00 12:00 23:59].each do |clock|
      assert_matches_legacy all_day, MONDAY, [clock]
      assert_matches_legacy equal, MONDAY, [clock]
      assert_matches_legacy end_of_day, MONDAY, [clock]
    end
  end

  test "break ranges are subtracted exactly" do
    shop = shop_with_json(
      "monday" => day(
        open: "09:00",
        close: "23:00",
        break_enabled: true,
        break_start: "14:00",
        break_end: "17:00"
      )
    )

    assert_matches_legacy shop, MONDAY, %w[13:59 14:00 16:59 17:00 22:59 23:00]
  end

  test "multiple text ranges match legacy parsing and boundaries" do
    shop = Shop.new(
      opening_hours_json: {},
      opening_hours_text: "月曜 11:00-14:00 / 月曜 17:00〜23:00"
    )

    assert_matches_legacy shop, MONDAY, %w[10:59 11:00 13:59 14:00 16:59 17:00 22:59 23:00]
  end

  test "closed missing blank and invalid data match legacy false results" do
    shops = [
      shop_with_json("monday" => { "closed" => true }),
      Shop.new(opening_hours_json: nil, opening_hours_text: nil),
      Shop.new(opening_hours_json: {}, opening_hours_text: ""),
      shop_with_json("monday" => day(open: "99:00", close: "18:00")),
      shop_with_json("monday" => { "open" => "09:00" })
    ]

    shops.each { |shop| assert_matches_legacy shop, MONDAY, %w[00:00 12:00 23:59] }
  end

  test "valid holiday text preserves the legacy all-week override" do
    shop = shop_with_json(
      { "monday" => { "closed" => true }, "tuesday" => { "closed" => true } },
      holiday_hours_text: "10:00-12:00"
    )

    assert_matches_legacy shop, MONDAY, %w[09:59 10:00 11:59 12:00]
    assert_matches_legacy shop, TUESDAY, %w[09:59 10:00 11:59 12:00]
  end

  test "invalid holiday text falls through to regular hours" do
    shop = shop_with_json(
      { "monday" => day(open: "09:00", close: "18:00") },
      holiday_hours_text: "祝日は要確認"
    )

    assert_matches_legacy shop, MONDAY, %w[08:59 09:00 17:59 18:00]
  end

  test "projection sync follows create and opening-hours updates without touching source values" do
    original_logger = AicooActivityLogger.method(:log)
    AicooActivityLogger.define_singleton_method(:log) { |**| { ok: true } }

    original_hours = { "monday" => day(open: "09:00", close: "18:00") }
    shop = Shop.create!(
      name: "営業時間派生テスト",
      address: "大阪府大阪市北区テスト1-1-1",
      genre: "バー",
      last_confirmed_on: Date.current,
      latitude: 34.6937,
      longitude: 135.5023,
      source: "test",
      opening_hours_json: original_hours
    )

    persisted_original_hours = shop.reload.opening_hours_json.deep_dup
    assert_equal [[9 * 60, 18 * 60]], windows_for(shop, 1)
    assert_equal persisted_original_hours, shop.reload.opening_hours_json

    updated_hours = { "monday" => day(open: "10:00", close: "20:00") }
    shop.update!(opening_hours_json: updated_hours)

    persisted_updated_hours = shop.reload.opening_hours_json.deep_dup
    assert_equal [[10 * 60, 20 * 60]], windows_for(shop, 1)
    assert_equal persisted_updated_hours, shop.reload.opening_hours_json
  ensure
    AicooActivityLogger.define_singleton_method(:log, original_logger) if original_logger
  end

  private

  def shop_with_json(hours = nil, holiday_hours_text: nil, **keyword_hours)
    hours = keyword_hours if hours.nil?
    Shop.new(opening_hours_json: hours, holiday_hours_text:)
  end

  def day(open:, close:, break_enabled: false, break_start: nil, break_end: nil)
    {
      "open" => open,
      "close" => close,
      "closed" => false,
      "break_enabled" => break_enabled,
      "break_start" => break_start,
      "break_end" => break_end
    }
  end

  def assert_matches_legacy(shop, date, clocks)
    clocks.each do |clock|
      hour, minute = clock.split(":").map(&:to_i)
      time = Time.zone.local(date.year, date.month, date.day, hour, minute)
      legacy = travel_to(time) { shop.open_now? }
      projected = ShopBusinessHoursProjection.open_at?(shop, time)

      assert_equal legacy, projected, "mismatch at #{time.iso8601}"
    end
  end

  def windows_for(shop, weekday)
    shop.business_hour_windows
        .where(weekday:)
        .order(:opens_at_minute)
        .pluck(:opens_at_minute, :closes_at_minute)
  end
end
