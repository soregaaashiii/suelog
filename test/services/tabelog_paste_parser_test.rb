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

  test "does not duplicate smoking ranges embedded in opening hour annotations" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      ヒャン
      営業時間
      月・火・水・木・金・土
      11:30 - 14:00
      17:00 - 22:00
      日
      定休日
      禁煙・喫煙
      分煙
      ランチタイム１１：３０～１３：００まで全席禁煙
    TEXT

    expected = %w[月 火 水 木 金 土].map do |day|
      "#{day} 13:00 - 14:00, 17:00 - 22:00"
    end.join("\n")

    assert_equal expected, result[:smoking_hours_text]
  end

  test "treats completely non-smoking wording as a timed non-smoking rule" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      完全禁煙時間テスト
      営業時間
      月
      11:30 - 14:00
      17:30 - 23:30
      禁煙・喫煙
      全席喫煙可
      11:00～17:00まで完全禁煙
    TEXT

    assert_equal "月 17:30 - 23:30", result[:smoking_hours_text]
  end

  test "marks a day unavailable when all of its opening hours are non-smoking" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      和 あいだ
      営業時間
      月・火・水・木・金
      11:30 - 14:00
      17:30 - 22:00
      土
      11:30 - 14:00
      日・祝日
      定休日
      禁煙・喫煙
      全席喫煙可
      11：30～14：00まで全面禁煙
    TEXT

    expected = %w[月 火 水 木 金].map { |day| "#{day} 17:30 - 22:00" }
    expected << "土 喫煙不可"

    assert_equal expected.join("\n"), result[:smoking_hours_text]
  end

  test "treats separated heated tobacco wording as smoking at the seat" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      加熱式分煙テスト
      禁煙・喫煙
      分煙（加熱式たばこ限定）
    TEXT

    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "electronic_only", result[:smoking_type]
    assert_nil result[:smoking_area_2]
    assert_nil result[:smoking_type_2]
  end

  test "extracts heated tobacco at seats and paper tobacco in smoking area separately" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      複合喫煙条件テスト
      禁煙・喫煙
      加熱式たばこは席で喫煙可、紙巻きたばこは喫煙所をご利用ください
    TEXT

    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "electronic_only", result[:smoking_type]
    assert_equal "separated", result[:smoking_area_2]
    assert_equal "paper_only", result[:smoking_type_2]
  end

  test "parses open ended lunch hours using the following dinner start" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      キッチンスタジアム
      営業時間
      ■ 営業時間
      [月～金]
      ランチ11時〜
      ディナー17:00〜22時
      ■定休日
      土曜日・日曜日、祝日
      禁煙・喫煙
      全席喫煙可
      ランチタイムは、禁煙になります
    TEXT

    %w[月 火 水 木 金].each do |day|
      assert_includes result[:opening_hours_text], "#{day} 11:00-17:00, 17:00-22:00"
      assert_includes result[:smoking_hours_text], "#{day} 17:00 - 22:00"
    end

    assert_equal "11:00", result[:opening_hours_json].dig("monday", "open")
    assert_equal "22:00", result[:opening_hours_json].dig("monday", "close")
    assert_equal "17:00", result[:opening_hours_json].dig("monday", "break_start")
    assert_equal "17:00", result[:opening_hours_json].dig("monday", "break_end")
  end

  test "parses next day dinner closing time after an open ended lunch" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      和囲炉
      営業時間
      ■ 営業時間
      ランチ／11：30～
      ※50食売切り
      ディナー／17:30～翌1:00
      ■ 定休日
      不定休お問い合わせ下さい。
      禁煙・喫煙
      全席喫煙可
      ランチタイム禁煙
    TEXT

    %w[月 火 水 木 金 土 日 祝日].each do |day|
      assert_includes result[:opening_hours_text], "#{day} 11:30-17:30, 17:30-25:00"
      assert_includes result[:smoking_hours_text], "#{day} 17:30 - 25:00"
    end

    assert_equal "11:30", result[:opening_hours_json].dig("monday", "open")
    assert_equal "25:00", result[:opening_hours_json].dig("monday", "close")
  end
end
