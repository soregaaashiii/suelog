require "test_helper"

class SmokingScheduleBadgesTest < ActionView::TestCase
  include RefineDesignHelper

  test "cards combine active tobacco types and always explain paper time" do
    shop = Shop.new(name: "時間切替", smoking_area: :all_smoking, smoking_type: :electronic_only,
      smoking_area_2: :all_smoking, smoking_type_2: :paper_only,
      opening_hours_text: "月 16:00-04:00", smoking_condition_schedules: {
        "primary" => { "mode" => "business" }, "secondary" => { "mode" => "custom", "hours_text" => "22:00-04:00" }
      })
    travel_to Time.zone.parse("2026-10-26 21:00") do
      html = refine_shop_smoking_badges(shop)
      assert_includes html, "加熱式のみ"
      refute_includes html, "紙・加熱式OK"
      assert_includes html, "22:00-04:00"
    end
    travel_to Time.zone.parse("2026-10-26 22:30") do
      assert_includes refine_shop_smoking_badges(shop), "紙・加熱式OK"
    end
  end
  test "seat location appears on cards without activating a time schedule" do
    shop = Shop.new(name: "テラス", smoking_area: :all_smoking, smoking_type: :both_ok,
      smoking_condition_schedules: { "primary" => { "seat_location" => "terrace" } })
    refute shop.advanced_smoking_schedules?
    assert_includes refine_shop_smoking_badges(shop), "テラス席"
    assert_includes refine_shop_smoking_badges(shop), "紙・加熱式OK"
    shop.smoking_area = :separated
    refute_includes refine_shop_smoking_badges(shop), "テラス席"
  end

  test "situational note is visible and safely escaped on cards" do
    shop = Shop.new(name: "状況による禁煙", smoking_area: :all_smoking, smoking_type: :both_ok,
      opening_hours_text: "月 11:00-23:00",
      smoking_condition_schedules: { "primary" => { "situation_note" => "お子様がいるときは禁煙 <script>alert(1)</script>" } })
    travel_to Time.zone.parse("2026-10-26 12:00") do
      html = refine_shop_smoking_badges(shop)
      assert_includes html, "状況により禁煙・要確認"
      assert_includes html, "お子様がいるときは禁煙"
      refute_includes html, "<script>"
      refute_includes html, "現在は喫煙不可"
    end
  end

end
