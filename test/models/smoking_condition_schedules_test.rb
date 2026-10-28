require "test_helper"

class SmokingConditionSchedulesTest < ActiveSupport::TestCase
  def shop_with_rules
    Shop.new(name: "時間切替", smoking_area: :all_smoking, smoking_type: :electronic_only,
      smoking_area_2: :all_smoking, smoking_type_2: :paper_only,
      opening_hours_text: "月 16:00-04:00\n火 16:00-04:00",
      smoking_condition_schedules: {
        primary: { mode: "business" }, secondary: { mode: "custom", hours_text: "22:00-04:00" }
      })
  end

  test "paper becomes available at 22 and stops at closing while heated stays available" do
    shop = shop_with_rules
    shop.valid? # Normalize form-shaped symbol keys.
    { "2026-10-26 21:59" => [true, false, "electronic_only"],
      "2026-10-26 22:00" => [true, true, "both_ok"],
      "2026-10-27 02:00" => [true, true, "both_ok"],
      "2026-10-27 04:00" => [false, false, nil],
      "2026-10-27 14:00" => [false, false, nil] }.each do |clock, (heated, paper, badge)|
      travel_to Time.zone.parse(clock) do
        assert_equal heated, shop.smoking_condition_now?("primary"), clock
        assert_equal paper, shop.smoking_condition_now?("secondary"), clock
        assert_equal heated || paper, shop.smoking_now?, clock
        actual_badge = shop.current_smoking_badge_conditions.first&.dig(:type)
        badge.nil? ? assert_nil(actual_badge, clock) : assert_equal(badge, actual_badge, clock)
      end
    end
  end

  test "unknown and whole-day bans do not grant permission and weekdays survive midnight" do
    shop = shop_with_rules
    shop.smoking_condition_schedules = { "primary" => { "mode" => "unknown" }, "secondary" => { "mode" => "custom", "hours_text" => "月 22:00-04:00\n火 18:00-23:00\n日 喫煙不可" } }
    travel_to Time.zone.parse("2026-10-27 02:00") do
      assert shop.smoking_condition_now?("secondary")
      refute shop.smoking_condition_now?("primary")
    end
    travel_to(Time.zone.parse("2026-10-27 17:00")) { refute shop.smoking_now? }
    shop.define_singleton_method(:open_now?) { true }
    shop.define_singleton_method(:holiday_today?) { true }
    travel_to(Time.zone.parse("2026-11-01 22:30")) { refute shop.smoking_condition_now?("secondary") }
  end

  test "business hours still exclude service breaks and confirmed nonsmoking overrides rules" do
    shop = shop_with_rules
    shop.opening_hours_text = "月 11:00-15:00, 17:00-23:00"
    shop.valid?
    travel_to(Time.zone.parse("2026-10-26 16:00")) { refute shop.smoking_now? }
    shop.define_singleton_method(:confirmed_non_smoking?) { true }
    travel_to(Time.zone.parse("2026-10-26 22:00")) { refute shop.smoking_now? }
  end

  test "legacy schedules remain unchanged and malformed advanced times are rejected" do
    shop = shop_with_rules
    shop.smoking_condition_schedules = {}
    shop.smoking_hours_text = "月 18:00-22:00"
    travel_to(Time.zone.parse("2026-10-26 17:00")) { refute shop.smoking_now? }
    travel_to(Time.zone.parse("2026-10-26 19:00")) { assert shop.smoking_now? }
    ["29:00-04:00", "22:80-04:00", "", "22:00-22:00", "月 適当な時間"].each do |text|
      shop.smoking_condition_schedules = { "secondary" => { "mode" => "custom", "hours_text" => text } }
      shop.valid?
      assert shop.errors[:base].any?, text
    end
  end
end
