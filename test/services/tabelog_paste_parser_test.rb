require "test_helper"

class TabelogPasteParserTest < ActiveSupport::TestCase
  test "hours without a pre or post holiday description use the regular schedule" do
    result = TabelogPasteParser.call(<<~TEXT)
      通常営業時間テスト店
      営業時間
      11:00 - 23:00
    TEXT

    assert_includes result[:opening_hours_text], "月 11:00-23:00"
    assert_equal "11:00", result[:opening_hours_json].dig("monday", "open")
    refute_includes result[:opening_hours_text].to_s, "祝前"
    refute_includes result[:opening_hours_text].to_s, "祝後"
    refute result[:opening_hours_json].key?("pre_holiday")
    refute result[:opening_hours_json].key?("post_holiday")
  end

  test "explicit pre and post holiday hours are parsed separately" do
    parser = TabelogPasteParser.new("")

    assert_equal ["pre_holiday"], parser.send(:expand_days, "祝前日")
    assert_equal ["post_holiday"], parser.send(:expand_days, "祝後日")
    assert_equal "祝前", parser.send(:day_label, "pre_holiday")
    assert_equal "祝後", parser.send(:day_label, "post_holiday")
  end

  test "keeps imported times that are not on a 15 minute boundary" do
    result = TabelogPasteParser.call(<<~TEXT)
      刻み外営業時間テスト店
      営業時間
      祝後日
      17:10 - 23:55
    TEXT

    assert_includes result[:opening_hours_text], "祝後 17:10-23:55"
    assert_equal "17:10", result[:opening_hours_json].dig("post_holiday", "open")
    assert_equal "23:55", result[:opening_hours_json].dig("post_holiday", "close")
  end
end
