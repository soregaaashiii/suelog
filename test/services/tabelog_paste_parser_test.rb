require "test_helper"

class TabelogPasteParserTest < ActiveSupport::TestCase
  test "separate nonsmoking and smoking seating areas import smoking seats" do
    ["禁煙席と喫煙席のエリアが分かれてます。", "喫煙席と禁煙席を分けています。"].each do |note|
      result = TabelogPasteParser.call("店名\nちょい吞み処 空見酒場\n営業時間\n月・火・水・木・金・土\n17:00 - 23:00\n日・祝日\n定休日\n禁煙・喫煙\n分煙\n#{note}\n駐車場\n無")
      assert_equal "all_smoking", result[:smoking_area]
      assert_equal "both_ok", result[:smoking_type]
      assert_nil result[:smoking_area_2]
      assert_includes result[:public_store_details], note
    end
    result = TabelogPasteParser.call("店名\n禁煙\n禁煙・喫煙\n分煙\n禁煙席のみで喫煙席なし\n駐車場\n無")
    refute_equal "all_smoking", result[:smoking_area]
  end

  test "counter-only timed ban keeps other seats available throughout business" do
    result = TabelogPasteParser.call("店名\nカフェ ララカ\n営業時間\n08:00 - 20:00\nL.O. 19:30\n禁煙・喫煙\n全席喫煙可\n8:00～14:00までカウンター席のみ禁煙\n駐車場\n無")
    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "all_smoking", result[:smoking_area_2]
    assert_equal "both_ok", result[:smoking_type]
    assert_equal "both_ok", result[:smoking_type_2]
    assert_nil result[:smoking_hours_text]
    assert_equal "non_counter", result.dig(:smoking_condition_schedules, "primary", "seat_location")
    assert_equal "14:00-20:00", result.dig(:smoking_condition_schedules, "secondary", "hours_text")
    assert_equal "counter", result.dig(:smoking_condition_schedules, "secondary", "seat_location")
    refute_includes result[:opening_hours_text], "喫煙可：14:00"
    shop = Shop.new(result.except(:import_metadata, :raw_import_text, :import_source, :imported_at))
    { "07:59" => [false, false], "08:00" => [true, false], "13:59" => [true, false], "14:00" => [true, true], "19:59" => [true, true], "20:00" => [false, false] }.each do |clock, (other, counter)|
      travel_to(Time.zone.parse("2026-10-26 #{clock}")) do
        assert_equal other, shop.smoking_condition_now?("primary"), clock
        assert_equal counter, shop.smoking_condition_now?("secondary"), clock
      end
    end
  end

  test "weekday nonsmoking with a reason keeps Saturday open but nonsmoking" do
    raw = "店名\nカフェ ツーボーイ\n営業時間\n月・火・水・木・金\n07:00 - 16:00\n土\n07:00 - 15:00\n日\n定休日\n禁煙・喫煙\n全席喫煙可\n土曜日はお子様連れが来られるので禁煙です\n駐車場\n有"
    result = TabelogPasteParser.call(raw)
    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "both_ok", result[:smoking_type]
    assert_includes result[:smoking_hours_text], "月 07:00 - 16:00"
    assert_includes result[:smoking_hours_text], "土 喫煙不可"
    assert_includes result[:opening_hours_text], "土 07:00-15:00"
    shop = Shop.new(result.except(:import_metadata, :raw_import_text, :import_source, :imported_at))
    travel_to(Time.zone.parse("2026-10-30 12:00")) { assert shop.smoking_now? }
    travel_to(Time.zone.parse("2026-10-31 12:00")) do
      assert shop.open_now?
      refute shop.smoking_now?
    end
    travel_to(Time.zone.parse("2026-11-01 12:00")) { refute shop.open_now? }
    partial = TabelogPasteParser.call(raw.sub("お子様連れが来られるので禁煙です", "ランチのお客様が来られるので禁煙です"))
    refute_includes partial[:smoking_hours_text].to_s, "土 喫煙不可"
  end

  test "explicit range followed by lunch-time wording keeps both smoking windows" do
    result = TabelogPasteParser.call("店名\nカフェ&レストラン マッシュ\n営業時間\n月・水・木・金・土・日\n09:30 - 20:30\nL.O. 20:00\n火\n定休日\n禁煙・喫煙\n全席喫煙可\n12：00〜13：00のランチタイムは禁煙\n駐車場\n無")
    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "both_ok", result[:smoking_type]
    assert_includes result[:smoking_hours_text], "月 09:30 - 12:00, 13:00 - 20:30"
    assert_equal result[:smoking_hours_text], result.dig(:smoking_condition_schedules, "primary", "hours_text")
    assert_includes result[:opening_hours_text], "09:30-20:30（L.O. 20:00）（喫煙可：09:30-12:00, 13:00-20:30）"
    shop = Shop.new(result.except(:import_metadata, :raw_import_text, :import_source, :imported_at))
    { "2026-10-26 09:29" => false, "2026-10-26 09:30" => true, "2026-10-26 12:00" => false, "2026-10-26 12:59" => false, "2026-10-26 13:00" => true, "2026-10-26 20:30" => false, "2026-10-27 14:00" => false }.each do |clock, allowed|
      travel_to(Time.zone.parse(clock)) { assert_equal allowed, shop.smoking_now?, clock }
    end
  end

  test "smoking bar floor with nonsmoking dance floor means smoking seats" do
    ["barフロアは喫煙　ダンスフロアは禁煙です", "バーフロアは喫煙可。ダンスフロアは禁煙"].each do |note|
      result = TabelogPasteParser.call("店名\nbar daphnia\n禁煙・喫煙\n分煙\n#{note}\n駐車場\n無")
      assert_equal "all_smoking", result[:smoking_area]
      assert_equal "both_ok", result[:smoking_type]
      assert_includes result[:public_store_details], note
      assert_nil result[:smoking_area_2]
    end
    result = TabelogPasteParser.call("店名\n禁止\n禁煙・喫煙\n分煙\nbarフロアは喫煙不可\n駐車場\n無")
    refute_equal "all_smoking", result[:smoking_area]
  end

  test "separate heated and paper starting hours import condition-specific schedules" do
    result = TabelogPasteParser.call("店名\n洋風ダイニングレーヴ\n営業時間\n月・火・木・金・土・日・祝日・祝前日・祝後日\n17:00 - 23:00\n水\n定休日\n禁煙・喫煙\n分煙（加熱式たばこ限定）\n17時～加熱式タバコ 21時～紙タバコ喫煙可能となっておます。\n駐車場\n無")
    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "electronic_only", result[:smoking_type]
    assert_equal "all_smoking", result[:smoking_area_2]
    assert_equal "both_ok", result[:smoking_type_2]
    assert_equal "17:00-23:00", result.dig(:smoking_condition_schedules, "primary", "hours_text")
    assert_equal "21:00-23:00", result.dig(:smoking_condition_schedules, "secondary", "hours_text")
    shop = Shop.new(result.except(:import_metadata, :raw_import_text, :import_source, :imported_at))
    { "2026-10-26 16:59" => nil, "2026-10-26 17:00" => "electronic_only", "2026-10-26 20:59" => "electronic_only", "2026-10-26 21:00" => "both_ok", "2026-10-26 23:00" => nil, "2026-10-28 21:00" => nil }.each do |clock, type|
      travel_to Time.zone.parse(clock) do
        actual = shop.current_smoking_badge_conditions.first&.dig(:type)
        type.nil? ? assert_nil(actual, clock) : assert_equal(type, actual, clock)
      end
    end
  end

  test "outside paper smoking becomes a second condition after heated-only seats" do
    ["店外にて紙タバコ喫煙可", "屋外で紙たばこ喫煙可能"].each do |note|
      result = TabelogPasteParser.call("店名\n朝日うまみ食堂\n禁煙・喫煙\n分煙（加熱式たばこ限定）\n#{note}\n駐車場\n有")
      assert_equal "all_smoking", result[:smoking_area]
      assert_equal "electronic_only", result[:smoking_type]
      assert_equal "separated", result[:smoking_area_2]
      assert_equal "both_ok", result[:smoking_type_2]
    end
    restricted = TabelogPasteParser.call("店名\n紙のみ\n禁煙・喫煙\n分煙（加熱式たばこ限定）\n店外にて紙タバコのみ喫煙可\n駐車場\n有")
    assert_equal "paper_only", restricted[:smoking_type_2]
    prohibited = TabelogPasteParser.call("店名\n禁煙\n禁煙・喫煙\n分煙（加熱式たばこ限定）\n店外にて紙タバコ喫煙不可\n駐車場\n有")
    assert_nil prohibited[:smoking_area_2]
  end

  test "full-width space before a timed ban preserves the smoking cutoff" do
    ["11:00～14:00　禁煙", "11:00～14:00 禁煙", "11:00～14:00禁煙"].each do |note|
      result = TabelogPasteParser.call("店名\n日光\n営業時間\n月・火・水・金・土・日\n11:00 - 21:00\n木\n定休日\n禁煙・喫煙\n全席喫煙可\n#{note}\n駐車場\n無")
      assert_includes result[:smoking_hours_text], "月 14:00 - 21:00", note
      assert_includes result[:opening_hours_text], "月 11:00-21:00（喫煙可：14:00-21:00）", note
      refute_includes result[:smoking_hours_text], "木 14:00", note
      shop = Shop.new(result.except(:import_metadata, :raw_import_text, :import_source, :imported_at))
      { "2026-10-26 13:59" => false, "2026-10-26 14:00" => true, "2026-10-26 21:00" => false, "2026-10-29 15:00" => false }.each do |clock, permitted|
        travel_to(Time.zone.parse(clock)) { assert_equal permitted, shop.smoking_now?, clock }
      end
    end
  end

  test "smoking at terrace seats accepts de-no wording and records terrace location" do
    ["テラス席での喫煙可", "テラス席で喫煙可"].each do |note|
      result = TabelogPasteParser.call("店名\nおだしと鶏のお店 ちゃぼ 長居店\n禁煙・喫煙\n分煙\n#{note}\n駐車場\n無")
      assert_equal "all_smoking", result[:smoking_area]
      assert_equal "both_ok", result[:smoking_type]
      assert_equal "terrace", result.dig(:smoking_condition_schedules, "primary", "seat_location")
    end
    result = TabelogPasteParser.call("店名\n禁煙\n禁煙・喫煙\n分煙\nテラス席での喫煙不可\n駐車場\n無")
    refute_equal "both_ok", result[:smoking_type]
  end

  test "lunch-time nonsmoking wording means seat smoking with unset times for continuous service" do
    %w[ランチ時間は禁煙 ランチ時間帯は禁煙 ランチ時は禁煙].each do |note|
      result = TabelogPasteParser.call("店名\nヤマダ カフェ\n営業時間\n火・水・木・金・土\n11:30 - 21:00\n日\n11:30 - 20:00\n月\n定休日\n禁煙・喫煙\n分煙\n#{note}\n駐車場\n有")
      assert_equal "all_smoking", result[:smoking_area], note
      assert_equal "both_ok", result[:smoking_type], note
      assert_nil result[:smoking_hours_text], note
      shop = Shop.new(result.except(:import_metadata, :raw_import_text, :import_source, :imported_at))
      assert shop.smoking_hours_unset_with_restriction?, note
    end
  end

  test "lunch nonsmoking separated seats use dinner hours and both tobacco types" do
    raw = "店名\n肉匠 牛虎 あびこ店\n営業時間\n月・火・水・木・金・土\n11:30 - 15:00\nL.O. 14:30\n17:00 - 00:00\nL.O. 23:00\n日\n11:30 - 15:00\n17:00 - 23:00\n禁煙・喫煙\n分煙\nランチ禁煙\n駐車場\n有"
    result = TabelogPasteParser.call(raw)
    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "both_ok", result[:smoking_type]
    assert_includes result[:smoking_hours_text], "月 17:00 - 00:00"
    assert_includes result[:smoking_hours_text], "日 17:00 - 23:00"
    refute_includes result[:smoking_hours_text], "11:30"
    outside = TabelogPasteParser.call(raw.sub("ランチ禁煙", "ランチ禁煙。屋外に喫煙所あり"))
    assert_equal "all_smoking", outside[:smoking_area]
    assert_equal "separated", outside[:smoking_area_2]
    assert_equal "both_ok", outside[:smoking_type_2]
    unknown = TabelogPasteParser.call("店名\n時間未設定\n営業時間\n11:30 - 23:00\n禁煙・喫煙\n分煙\nランチ禁煙\n駐車場\n無")
    assert_equal "all_smoking", unknown[:smoking_area]
    assert_nil unknown[:smoking_hours_text]
  end

  test "heated throughout business with paper after 22 imports advanced schedules" do
    result = TabelogPasteParser.call("店名\nとりいちず 西九条店\n営業時間\n月・火・水・木・金\n16:00 - 04:00\n土・日・祝日\n13:00 - 04:00\n禁煙・喫煙\n全席喫煙可\n※加熱式タバコ限定（22時以降、紙タバコも喫煙可）\n駐車場\n無")
    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "electronic_only", result[:smoking_type]
    assert_equal "all_smoking", result[:smoking_area_2]
    assert_equal "both_ok", result[:smoking_type_2]
    assert_equal "business", result[:smoking_condition_schedules].dig("primary", "mode")
    assert_equal "22:00-04:00", result[:smoking_condition_schedules].dig("secondary", "hours_text")
    assert_nil result[:smoking_hours_text]
    refute_includes result[:opening_hours_text], "喫煙可：22:00"
    shop = Shop.new(result.except(:import_metadata, :raw_import_text, :import_source, :imported_at))
    travel_to(Time.zone.parse("2026-10-26 21:59")) do
      assert_equal [{ area: "all_smoking", type: "electronic_only" }], shop.current_smoking_badge_conditions
    end
    travel_to(Time.zone.parse("2026-10-26 22:00")) do
      assert_equal [{ area: "all_smoking", type: "both_ok" }], shop.current_smoking_badge_conditions
    end
    travel_to(Time.zone.parse("2026-10-27 03:59")) do
      assert_equal [{ area: "all_smoking", type: "both_ok" }], shop.current_smoking_badge_conditions
    end
    travel_to(Time.zone.parse("2026-10-27 04:00")) { refute shop.smoking_now? }

  end

  test "partially smoking terrace seats allow both tobacco types at seats" do
    result = TabelogPasteParser.call("店名\nSAILS 大阪\n禁煙・喫煙\n分煙\n室内は禁煙。テラス席の一部喫煙可。\n駐車場\n有")
    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "both_ok", result[:smoking_type]
    assert_includes result[:public_store_details], "室内は禁煙。テラス席の一部喫煙可。"
    assert_equal "terrace", result.dig(:smoking_condition_schedules, "primary", "seat_location")
    result = TabelogPasteParser.call("店名\n禁煙テラス\n禁煙・喫煙\n分煙\nテラス席の一部喫煙不可。\n駐車場\n有")
    refute_equal "both_ok", result[:smoking_type]
  end

  test "smoking permitted only in terrace seat section means seat smoking and both types" do
    ["２階テラス席部分のみ喫煙可能", "2階テラス席エリアのみ喫煙可"].each do |note|
      result = TabelogPasteParser.call("店名\nビア スタンド マルカ\n禁煙・喫煙\n分煙\n#{note}\n駐車場\n無")
      assert_equal "all_smoking", result[:smoking_area]
      assert_equal "both_ok", result[:smoking_type]
      assert_nil result[:smoking_area_2]
      assert_includes result[:public_store_details], note
    end
    result = TabelogPasteParser.call("店名\nテラス禁煙\n禁煙・喫煙\n分煙\n２階テラス席部分のみ喫煙不可\n駐車場\n無")
    refute_equal "all_smoking", result[:smoking_area]
  end

  test "floor smoking seats and an outdoor smoking area retain both conditions" do
    ["2、3F席喫煙可1F禁煙席となります。店外にも喫煙所あり。", "2、3階席喫煙可1階禁煙席。店外にも喫煙所あり。"].each do |note|
      result = TabelogPasteParser.call("店名\n小川下 喜多呂\n禁煙・喫煙\n分煙\n#{note}\n駐車場\n無")
      assert_equal "all_smoking", result[:smoking_area]
      assert_equal "both_ok", result[:smoking_type]
      assert_equal "separated", result[:smoking_area_2]
      assert_equal "both_ok", result[:smoking_type_2]
      assert_includes result[:public_store_details], note
    end
    result = TabelogPasteParser.call("店名\n店外のみ\n禁煙・喫煙\n分煙\n3F席喫煙不可。店外にも喫煙所あり。\n駐車場\n無")
    refute_equal "all_smoking", result[:smoking_area]
  end

  test "separated smoking with nonsmoking tatami seats retains smoking seats" do
    result = TabelogPasteParser.call("店名\n焼肉 しろ\n禁煙・喫煙\n分煙\n座敷席は禁煙席\n駐車場\n無")
    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "both_ok", result[:smoking_type]
    assert_nil result[:smoking_area_2]
    assert_includes result[:public_store_details], "座敷席は禁煙席"
    result = TabelogPasteParser.call("店名\n禁煙店\n禁煙・喫煙\n全席禁煙\n座敷席は禁煙席\n駐車場\n無")
    refute_equal "all_smoking", result[:smoking_area]
  end

  test "adjacent nonsmoking and smoking periods use only the smoking interval" do
    ["11:30〜14:00禁煙16:30〜22:00喫煙可", "16:30〜22:00喫煙可、11:30〜14:00禁煙"].each do |note|
      result = TabelogPasteParser.call("店名\n国産鶏焼肉 和気あいあい\n営業時間\n月・火・木・金・土・日\n11:30 - 14:00\n16:30 - 22:00\nL.O. 21:30\n水\n定休日\n禁煙・喫煙\n全席喫煙可\n#{note}\n駐車場\n無")
      %w[月 火 木 金 土 日].each do |day|
        assert_includes result[:smoking_hours_text], "#{day} 16:30 - 22:00"
      end
      refute_match(/^水 \d/, result[:smoking_hours_text])
      assert_includes result[:opening_hours_text], "喫煙可：16:30-22:00"
      refute_match(/喫煙可：11:30-14:00/, result[:opening_hours_text])
      assert_includes result[:opening_hours_text], "L.O. 21:30"
      assert_includes result[:public_store_details], note
    end
  end

  test "weekday hours override repeated meal notes and parenthesized lunch ban starts at 14" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      Garage Craft
      営業時間
      月・火・水・木・金・土・祝日・祝前日・祝後日
      11:30 - 15:00
      L.O. 14:30
      17:30 - 23:30
      L.O. 料理22:30 ドリンク23:00
      日
      定休日
      ■ 営業時間
      ランチ:11:30〜15:00 LO14:45
      ディナー:17:30〜23:30 LO23:00
      予算
      ～￥999
      禁煙・喫煙
      全席喫煙可
      (紙タバコ不可) ランチタイム(11:30～14:00)のみ全面禁煙
      駐車場
      無
    TEXT
    %w[月 火 水 木 金 土 祝日 祝前 祝後].each do |day|
      line = result[:opening_hours_text].lines.find { |entry| entry.start_with?("#{day} ") }
      assert_equal 1, line.scan("11:30-15:00").size
      assert_equal 1, line.scan("17:30-23:30").size
      assert_includes line, "L.O. 14:30"
      assert_includes line, "料理22:30 ドリンク23:00"
      assert_includes result[:smoking_hours_text], "#{day} 14:00 - 23:30"
    end
    refute_match(/^日 \d/, result[:smoking_hours_text])
    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "electronic_only", result[:smoking_type]
  end

  test "table smoking with nonsmoking counter means smoking seats and both types" do
    result = TabelogPasteParser.call("店名\n石鹿\n禁煙・喫煙\n分煙\nカウンター禁煙/テーブル喫煙\n駐車場\n無")
    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "both_ok", result[:smoking_type]
    assert_nil result[:smoking_area_2]
    assert_includes result[:public_store_details], "カウンター禁煙/テーブル喫煙"
    result = TabelogPasteParser.call("店名\n禁煙テーブル\n禁煙・喫煙\n分煙\nテーブル喫煙不可\n駐車場\n無")
    refute_equal "all_smoking", result[:smoking_area]
  end

  test "morning nonsmoking means smoking from noon until closing on operating days" do
    result = TabelogPasteParser.call("店名\n喫茶 むらかみ\n営業時間\n火・水・木・金・土\n08:00 - 17:00\n月・日\n定休日\n禁煙・喫煙\n全席喫煙可\n午前中は喫煙不可\n駐車場\n無")
    %w[火 水 木 金 土].each do |day|
      assert_includes result[:smoking_hours_text], "#{day} 12:00 - 17:00"
      assert_includes result[:opening_hours_text], "#{day} 08:00-17:00（喫煙可：12:00-17:00）"
    end
    refute_match(/[月日] \d/, result[:smoking_hours_text])
    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "both_ok", result[:smoking_type]
    assert_includes result[:public_store_details], "午前中は喫煙不可"
  end

  test "morning only business remains nonsmoking after morning ban" do
    result = TabelogPasteParser.call("店名\n午前営業\n営業時間\n08:00 - 11:00\n禁煙・喫煙\n全席喫煙可\n午前中は禁煙\n駐車場\n無")
    assert_includes result[:smoking_hours_text], "月 喫煙不可"
    refute_match(/12:00 - 11:00/, result[:smoking_hours_text])
  end

  test "AM lunch ban with a PM end and outdoor permission preserves both conditions" do
    result = TabelogPasteParser.call("店名\n二両半 鶴橋本店\n営業時間\n月・火・木・金・土・日\n11:00 - 03:00\n水\n定休日\n禁煙・喫煙\n全席喫煙可\nランチタイムAM11~2時まで店内禁煙　店外は喫煙OK\n駐車場\n無")
    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "both_ok", result[:smoking_type]
    assert_equal "separated", result[:smoking_area_2]
    assert_equal "both_ok", result[:smoking_type_2]
    %w[月 火 木 金 土 日].each { |day| assert_includes result[:smoking_hours_text], "#{day} 14:00 - 03:00" }
    refute_match(/水 \d/, result[:smoking_hours_text])
    assert_includes result[:opening_hours_text], "喫煙可：14:00-03:00"
    assert_includes result[:public_store_details], "店外は喫煙OK"
  end

  test "kanji floor smoking permission means seat smoking" do
    ["一階は喫煙可　二階は禁煙", "１階は喫煙可、２階は禁煙"].each do |note|
      result = TabelogPasteParser.call("店名\n炭火屋 一\n禁煙・喫煙\n分煙\n#{note}\n駐車場\n無")
      assert_equal "all_smoking", result[:smoking_area]
      assert_equal "both_ok", result[:smoking_type]
      assert_includes result[:public_store_details], note
    end
    result = TabelogPasteParser.call("店名\n禁煙店\n禁煙・喫煙\n分煙\n一階は喫煙不可　二階は禁煙\n駐車場\n無")
    refute_equal "all_smoking", result[:smoking_area]
  end

  test "separated smoking with a nonsmoking floor means smoking seats elsewhere" do
    ["二階席は禁煙です", "２階の席が禁煙"].each do |note|
      result = TabelogPasteParser.call("店名\n馬肉料理専門店 馬郎\n禁煙・喫煙\n分煙\n#{note}\n駐車場\n無")
      assert_equal "all_smoking", result[:smoking_area]
      assert_equal "both_ok", result[:smoking_type]
      assert_includes result[:public_store_details], note
    end
    result = TabelogPasteParser.call("店名\n禁煙店\n禁煙・喫煙\n全席禁煙\n二階席は禁煙です\n駐車場\n無")
    refute_equal "all_smoking", result[:smoking_area]
  end

  test "counted terrace smoking seats mean seat smoking and both tobacco types" do
    ["禁煙38席・喫煙（テラス）6席", "禁煙38席・喫煙(テラス席)６席"].each do |note|
      result = TabelogPasteParser.call("店名\nル・クロワッサン 鶴見緑地店\n禁煙・喫煙\n分煙\n#{note}\n駐車場\n有")
      assert_equal "all_smoking", result[:smoking_area]
      assert_equal "both_ok", result[:smoking_type]
      assert_nil result[:smoking_area_2]
      assert_includes result[:public_store_details], note
    end
    result = TabelogPasteParser.call("店名\nゼロ席\n禁煙・喫煙\n分煙\n喫煙（テラス）0席\n駐車場\n無")
    refute_equal "all_smoking", result[:smoking_area]
  end

  test "heated tobacco indoors and paper tobacco in a dedicated space produce two conditions" do
    result = TabelogPasteParser.call("店名\nカラオケサロンバーレッドリバー\n禁煙・喫煙\n分煙（加熱式たばこ限定）\n加熱式タバコ⇒店内喫煙可、紙タバコ⇒屋内に専用スペース有\n駐車場\n無")
    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "electronic_only", result[:smoking_type]
    assert_equal "separated", result[:smoking_area_2]
    assert_equal "both_ok", result[:smoking_type_2]
    assert_includes result[:public_store_details], "紙タバコ⇒屋内に専用スペース有"
  end

  test "paper tobacco only prohibited means heated tobacco only at seats" do
    ["紙タバコのみ禁煙", "紙たばこだけは禁止", "紙巻き煙草のみ喫煙不可"].each do |note|
      result = TabelogPasteParser.call("店名\n太郎\n営業時間\n木・金・土・日\n17:00 - 22:00\n月・火・水\n定休日\n禁煙・喫煙\n全席喫煙可\n#{note}\n駐車場\n無")
      assert_equal "all_smoking", result[:smoking_area]
      assert_equal "electronic_only", result[:smoking_type]
      assert_nil result[:smoking_area_2]
      assert_includes result[:public_store_details], note
    end
  end

  test "paper tobacco only permission is not a prohibition" do
    result = TabelogPasteParser.call("店名\n紙限定店\n禁煙・喫煙\n全席喫煙可\n紙タバコのみ喫煙可\n駐車場\n無")
    assert_equal "paper_only", result[:smoking_type]
  end

  test "separate weekday bans are all imported without treating partial bans as whole days" do
    result = TabelogPasteParser.call("店名\n曜日テスト\n営業時間\n11:00 - 23:00\n禁煙・喫煙\n全席喫煙可\n月曜日は終日禁煙。水・金のみ全面禁煙\n駐車場\n無")
    %w[月 水 金].each { |day| assert_includes result[:smoking_hours_text], "#{day} 喫煙不可" }
    %w[火 木 土 日].each { |day| assert_includes result[:smoking_hours_text], "#{day} 11:00 - 23:00" }
  end

  test "Sunday only nonsmoking overrides all seat smoking without closing the shop" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      炭火焼鳥酒場 いろとりどり
      営業時間
      月・火・木・金・土・日・祝日・祝前日・祝後日
      17:00 - 01:00
      水
      定休日
      ■定休日
      水曜日、不定休
      禁煙・喫煙
      全席喫煙可
      日曜日のみ全席禁煙
      駐車場
      無
    TEXT
    assert_includes result[:smoking_hours_text], "日 喫煙不可"
    %w[月 火 木 金 土 祝日 祝前 祝後].each { |day| assert_includes result[:smoking_hours_text], "#{day} 17:00 - 01:00" }
    assert_includes result[:opening_hours_text], "日 17:00-01:00"
    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "both_ok", result[:smoking_type]
    assert_includes result[:public_store_details], "日曜日のみ全席禁煙"
    refute_match(/水 \d/, result[:smoking_hours_text])
  end

  test "positive smoking seat counts including fullwidth numbers mean seat smoking" do
    ["禁煙席：３０席／喫煙席：１８席", "禁煙席:30席/喫煙席:18席"].each do |note|
      result = TabelogPasteParser.call("店名\nミスタードーナツ 都島ショップ\n禁煙・喫煙\n分煙\n#{note}\n駐車場\n無")
      assert_equal "all_smoking", result[:smoking_area]
      assert_equal "both_ok", result[:smoking_type]
      assert_nil result[:smoking_area_2]
      assert_includes result[:public_store_details], note
    end
  end

  test "zero smoking seats are not a positive smoking condition" do
    result = TabelogPasteParser.call("店名\nゼロ席テスト\n禁煙・喫煙\n分煙\n禁煙席：３０席／喫煙席：０席\n駐車場\n無")
    refute_equal "all_smoking", result[:smoking_area]
  end

  test "counted smoking seats preserve explicit heated tobacco restriction" do
    result = TabelogPasteParser.call("店名\n限定席テスト\n禁煙・喫煙\n分煙\n喫煙席：１８席（加熱式のみ）\n駐車場\n無")
    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "electronic_only", result[:smoking_type]
  end

  test "floor smoking seat rule does not turn smoking prohibited into permission" do
    result = TabelogPasteParser.call("店名\n禁煙テスト\n禁煙・喫煙\n全席禁煙\n1階席が喫煙不可、2階席も禁煙です。\n駐車場\n無")
    refute_equal "all_smoking", result[:smoking_area]
  end

  test "smoking seats on one floor remain seat smoking when another floor is nonsmoking" do
    result = TabelogPasteParser.call("店名\nこてこて 都島店\n禁煙・喫煙\n分煙\n1階席が喫煙、2階席が禁煙となります。\n駐車場\n無")
    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "both_ok", result[:smoking_type]
    assert_nil result[:smoking_area_2]
    assert_includes result[:public_store_details], "1階席が喫煙、2階席が禁煙"
  end

  test "parenthesized smoking allowed and explicit meal hours override broad summary" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      丸万寿司 OAP店
      営業時間
      11:00 - 21:00
      L.O. 20:30
      ■ 営業時間
      ランチ 11：00～15：00
      ディナー17：00～21：00
      ■ 定休日
      不定休（ビル休館日に準ずる）
      禁煙・喫煙
      分煙
      13：00まで禁煙/13:00以降喫煙（可）
      駐車場
      有
    TEXT
    %w[月 火 水 木 金 土 日 祝日].each { |day| assert_includes result[:smoking_hours_text], "#{day} 13:00 - 21:00" }
    assert_equal "15:00", result[:opening_hours_json].dig("monday", "break_start")
    assert_equal "17:00", result[:opening_hours_json].dig("monday", "break_end")
    refute_includes result[:opening_hours_text], "11:00-21:00"
  end

  test "weekend holiday cutoff does not restrict weekday smoking" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      凡僧 都島店
      営業時間
      火・水・木・金・土
      17:00 - 00:00
      L.O. 23:00
      日・祝日
      17:00 - 23:00
      L.O. 22:00
      月
      定休日
      禁煙・喫煙
      分煙
      土、日、祝日は20時まで禁煙となります。お子様連れの方は電話で確認してください
      駐車場
      無
    TEXT
    %w[火 水 木 金].each { |day| assert_includes result[:smoking_hours_text], "#{day} 17:00 - 00:00" }
    assert_includes result[:smoking_hours_text], "土 20:00 - 00:00"
    %w[日 祝日].each { |day| assert_includes result[:smoking_hours_text], "#{day} 20:00 - 23:00" }
    refute_match(/月 \d/, result[:smoking_hours_text])
    assert_includes result[:public_store_details], "お子様連れの方は電話で確認してください"
  end

  test "parenthesized lunch ban preserves smoking before and after lunch" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      大一そば
      営業時間
      月・水・木・金
      10:30 - 20:45
      土・日・祝日
      09:00 - 20:45
      火
      定休日
      禁煙・喫煙
      全席喫煙可
      ※ランチ時（11:30~14:00）禁煙
      駐車場
      無
    TEXT
    %w[月 水 木 金].each { |day| assert_includes result[:smoking_hours_text], "#{day} 10:30 - 11:30, 14:00 - 20:45" }
    %w[土 日 祝日].each { |day| assert_includes result[:smoking_hours_text], "#{day} 09:00 - 11:30, 14:00 - 20:45" }
    refute_match(/火 \d/, result[:smoking_hours_text])
    assert_includes result[:public_store_details], "11:30~14:00"
  end

  test "separated smoking with nonsmoking seats is smoking at seats with the note preserved" do
    result = TabelogPasteParser.call("店名\nがんこ 十三総本店\n禁煙・喫煙\n分煙\n禁煙席あり\n駐車場\n無")
    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "both_ok", result[:smoking_type]
    assert_nil result[:smoking_area_2]
    assert_includes result[:public_store_details], "禁煙席あり"
  end

  test "plain separated smoking remains unknown and explicit heated restriction is preserved" do
    result = TabelogPasteParser.call("店名\n不明テスト\n禁煙・喫煙\n分煙\n駐車場\n無")
    assert_equal "unknown", result[:smoking_area]
    assert_equal "unknown", result[:smoking_type]
    result = TabelogPasteParser.call("店名\n限定テスト\n禁煙・喫煙\n分煙（加熱式たばこ限定）\n禁煙席あり\n駐車場\n無")
    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "electronic_only", result[:smoking_type]
  end

  test "breakfast nonsmoking excludes breakfast only days" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      カフェ・ド・カプリス
      営業時間
      月・火・水・木・金
      06:30 - 09:30
      11:30 - 14:00
      土・日
      07:00 - 09:30
      ■ 定休日
      不定休
      禁煙・喫煙
      分煙
      時間分煙（朝食時禁煙、それ以外喫煙可）
      空間・設備
      カウンター席あり
    TEXT
    %w[月 火 水 木 金].each { |day| assert_includes result[:smoking_hours_text], "#{day} 11:30 - 14:00" }
    %w[土 日].each { |day| assert_includes result[:smoking_hours_text], "#{day} 喫煙不可" }
    refute_includes result[:smoking_hours_text], "09:30"
    assert_includes result[:public_store_details], "朝食時禁煙"
  end

  test "breakfast nonsmoking without separate hours remains unknown" do
    result = TabelogPasteParser.call("店名\n朝食テスト\n営業時間\n06:30 - 14:00\n禁煙・喫煙\n分煙\n朝食時禁煙、それ以外喫煙可\n駐車場\n無")
    assert_nil result[:smoking_hours_text]
    assert Shop.new(public_store_details: result[:public_store_details]).smoking_hours_unset_with_restriction?
  end

  test "paper smoking area without an exclusive qualifier accepts both types" do
    ["外に紙タバコ喫煙所あり", "外に紙たばこ喫煙所あり", "紙巻きたばこ喫煙ブースあり"].each do |note|
      result = TabelogPasteParser.call("店名\n立ち飲み酒場ほっ\n禁煙・喫煙\n分煙（加熱式たばこ限定）\n#{note}\n駐車場\n無")
      assert_equal "all_smoking", result[:smoking_area]
      assert_equal "electronic_only", result[:smoking_type]
      assert_equal "separated", result[:smoking_area_2]
      assert_equal "both_ok", result[:smoking_type_2]
    end
  end

  test "explicit paper only qualifiers remain paper only in a separate area" do
    %w[のみ だけ 限定 専用].each do |qualifier|
      result = TabelogPasteParser.call("店名\n限定テスト\n禁煙・喫煙\n分煙（加熱式たばこ限定）\n外に紙タバコ#{qualifier}の喫煙所あり\n駐車場\n無")
      assert_equal "electronic_only", result[:smoking_type]
      assert_equal "paper_only", result[:smoking_type_2]
    end
  end

  test "standalone paper only qualifiers are not broadened" do
    %w[のみ だけ 限定 専用].each do |qualifier|
      result = TabelogPasteParser.call("店名\n紙限定テスト\n禁煙・喫煙\n紙タバコ#{qualifier}喫煙可\n駐車場\n無")
      assert_equal "paper_only", result[:smoking_type]
    end
  end

  test "partial lunch nonsmoking with unknown times does not mistake breakfast and lunch for dinner" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      レストラン プレノール
      営業時間
      月
      07:00 - 09:30
      11:30 - 13:30
      火・水・木・金
      07:00 - 09:30
      11:30 - 13:30
      17:30 - 21:30
      L.O. 21:00
      土
      07:00 - 09:30
      17:30 - 21:30
      L.O. 21:00
      日・祝日
      定休日
      禁煙・喫煙
      分煙
      ランチタイムは禁煙タイムあります
      駐車場
      有
    TEXT
    assert_nil result[:smoking_hours_text]
    assert_includes result[:public_store_details], "ランチタイムは禁煙タイムあります"
    refute_includes result[:opening_hours_text], "喫煙可："
    assert Shop.new(public_store_details: result[:public_store_details]).smoking_hours_unset_with_restriction?
  end

  test "prefix nonsmoking times without parentheses exclude lunch only service" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      長芋ざんまい とろろん
      営業時間
      月
      11:30 - 14:30
      L.O. 14:00
      火・水・木・金
      11:30 - 14:30
      L.O. 14:00
      18:00 - 22:00
      L.O. 21:30
      土
      18:00 - 22:00
      L.O. 21:30
      日・祝日
      定休日
      月曜日（昼のみ営業）
      土曜日（夜のみ営業）
      禁煙・喫煙
      分煙
      時間帯禁煙11:30~14:30
      駐車場
      無
    TEXT
    assert_includes result[:smoking_hours_text], "月 喫煙不可"
    %w[火 水 木 金 土].each { |day| assert_includes result[:smoking_hours_text], "#{day} 18:00 - 22:00" }
    refute_match(/(?:日|祝日) \d/, result[:smoking_hours_text])
    assert_includes result[:public_store_details], "時間帯禁煙11:30~14:30"
  end

  test "weekday nonsmoking with weekend holiday exception preserves full weekend hours" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      インド料理 ムマインビテーション
      営業時間
      11:00 - 14:30
      L.O. 14:30
      17:00 - 22:30
      L.O. 22:30
      ■ 定休日
      無休
      禁煙・喫煙
      全席喫煙可
      平日11:00～13:30は禁煙（土・日・祝　喫煙可）
      駐車場
      無
    TEXT
    %w[月 火 水 木 金].each { |day| assert_includes result[:smoking_hours_text], "#{day} 13:30 - 22:30" }
    %w[土 日 祝日].each { |day| assert_includes result[:smoking_hours_text], "#{day} 11:00 - 22:30" }
    assert_equal "14:30", result[:opening_hours_json].dig("saturday", "break_start")
    assert_equal "17:00", result[:opening_hours_json].dig("saturday", "break_end")
    assert_includes result[:public_store_details], "土・日・祝"
  end

  test "only completely nonsmoking with fullwidth times preserves each days closing time" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      そばよし 西中島店
      営業時間
      月・火・水
      11:00 - 15:00
      17:00 - 22:00
      木
      11:00 - 22:00
      金
      11:00 - 17:00
      土
      11:00 - 21:30
      日
      定休日
      禁煙・喫煙
      全席喫煙可
      11：00～13：30のみ全面禁煙
      駐車場
      無
    TEXT
    %w[月 火 水 木].each { |day| assert_includes result[:smoking_hours_text], "#{day} 13:30 - 22:00" }
    assert_includes result[:smoking_hours_text], "金 13:30 - 17:00"
    assert_includes result[:smoking_hours_text], "土 13:30 - 21:30"
    refute_match(/日 \d/, result[:smoking_hours_text])
    assert_equal "15:00", result[:opening_hours_json].dig("monday", "break_start")
    assert_equal "17:00", result[:opening_hours_json].dig("monday", "break_end")
    assert_includes result[:public_store_details], "13：30のみ全面禁煙"
  end

  test "morning nonsmoking range keeps a single smoking window across lunch break" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      一番どり 西中島店
      営業時間
      月・火・水・木・金・土
      11:30 - 15:00
      18:00 - 23:00
      日・祝日
      定休日
      禁煙・喫煙
      分煙
      11時から14時まで全面禁煙
      駐車場
      無
    TEXT
    %w[月 火 水 木 金 土].each { |day| assert_includes result[:smoking_hours_text], "#{day} 14:00 - 23:00" }
    refute_includes result[:smoking_hours_text], "15:00"
    refute_match(/(?:日|祝日) \d/, result[:smoking_hours_text])
    assert_equal "15:00", result[:opening_hours_json].dig("monday", "break_start")
    assert_equal "18:00", result[:opening_hours_json].dig("monday", "break_end")
  end

  test "smoking cutoff spans the service break as a single editable window" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      魚居酒屋 すなおや 西中島本店
      営業時間
      月・火・水・木・金
      11:30 - 15:00
      L.O. 14:30
      17:00 - 23:00
      L.O. 22:20
      土・日・祝日
      11:30 - 23:00
      L.O. 22:20
      禁煙・喫煙
      分煙
      ランチタイム13時までは全席禁煙です。
      駐車場
      無
    TEXT
    %w[月 火 水 木 金 土 日 祝日].each { |day| assert_includes result[:smoking_hours_text], "#{day} 13:00 - 23:00" }
    assert_equal "15:00", result[:opening_hours_json].dig("monday", "break_start")
    assert_equal "17:00", result[:opening_hours_json].dig("monday", "break_end")
    refute_includes result[:smoking_hours_text], "15:00"
    assert_includes result[:opening_hours_text], "喫煙可：13:00-23:00"
  end

  test "weekday start and weekend holiday full smoking are separate schedules" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      昴 新大阪店
      営業時間
      11:00 - 00:00
      ■ 営業時間
      売切次第終了
      ■ 定休日
      無休
      禁煙・喫煙
      分煙
      平日：14:00～、土日祝：終日喫煙可
      駐車場
      無
    TEXT
    %w[月 火 水 木 金].each do |day|
      assert_includes result[:smoking_hours_text], "#{day} 14:00 - 00:00"
      assert_match(/#{day}.*喫煙可：14:00-00:00/, result[:opening_hours_text])
    end
    %w[土 日 祝日].each do |day|
      assert_includes result[:smoking_hours_text], "#{day} 11:00 - 00:00"
    end
    assert_includes result[:public_store_details], "平日：14:00～、土日祝：終日喫煙可"
  end

  test "night only smoking follows the evening service and excludes closed days" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      隆勝
      （リュウショウ）
      営業時間
      月・火・木・金・土・日
      11:00 - 14:30
      17:30 - 02:00
      水
      定休日
      禁煙・喫煙
      分煙
      夜だけ喫煙可
      駐車場
      無
    TEXT
    %w[月 火 木 金 土 日].each do |day|
      assert_includes result[:smoking_hours_text], "#{day} 17:30 - 02:00"
      assert_match(/#{day}.*喫煙可：17:30-02:00/, result[:opening_hours_text])
    end
    assert_includes result[:smoking_hours_text], "水 喫煙不可"
    refute_includes result[:smoking_hours_text], "14:30"
    assert_includes result[:public_store_details], "夜だけ喫煙可"
  end

  test "night only smoking with no separate evening hours stays unknown" do
    result = TabelogPasteParser.call("店名\n夜限定テスト\n営業時間\n11:00 - 23:00\n禁煙・喫煙\n分煙\n夜だけ喫煙可\n駐車場\n無")
    assert_nil result[:smoking_hours_text]
    shop = Shop.new(public_store_details: result[:public_store_details])
    assert shop.smoking_hours_unset_with_restriction?
  end

  test "nonsmoking range written with kara and time period is excluded" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      新大阪 海鮮食堂 おーうえすと
      営業時間
      11:30 - 00:00
      L.O. 23:00
      禁煙・喫煙
      全席喫煙可
      11:30から13:00の時間帯は全席禁煙です。
      駐車場
      無
    TEXT
    %w[月 火 水 木 金 土 日 祝日].each do |day|
      assert_includes result[:smoking_hours_text], "#{day} 13:00 - 00:00"
    end
    assert_includes result[:opening_hours_text], "11:30-00:00"
    assert_includes result[:public_store_details], "11:30から13:00の時間帯は全席禁煙"
  end

  test "lunch nonsmoking without lunch times leaves smoking hours unset" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      大悟
      （ダイゴ）
      ジャンル 洋食
      住所
      大阪府大阪市中央区上汐2-2-12
      営業時間
      月・火・水・木・金・土
      11:00 - 21:00
      日
      定休日
      禁煙・喫煙
      分煙
      ランチタイム禁煙
      駐車場
      無
    TEXT

    assert_nil result[:smoking_hours_text]
    assert_nil result[:import_metadata][:smoking_hours_text]
    assert_includes result[:public_store_details], "ランチタイム禁煙"
    assert_includes result[:opening_hours_text], "月 11:00-21:00"
    refute_includes result[:opening_hours_text], "喫煙可："
  end

  test "daytime nonsmoking does not become smoking after lunch on lunch-only days" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      First Flower
      営業時間
      月・火
      11:00 - 16:00
      木・金・土・日
      11:00 - 16:00
      18:00 - 22:30
      水
      定休日
      ランチ11:00〜14:30
      テイクアウト11:00〜16:00
      焼き鳥(木)〜(日)
      18:00〜22:30
      禁煙・喫煙
      分煙
      昼、禁煙　　夜、喫煙可
    TEXT
    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "both_ok", result[:smoking_type]
    %w[月 火].each { |day| assert_includes result[:smoking_hours_text], "#{day} 喫煙不可" }
    %w[木 金 土 日].each { |day| assert_includes result[:smoking_hours_text], "#{day} 18:00 - 22:30" }
    refute_includes result[:smoking_hours_text], "14:30"
    refute_match(/水.*11:00/, result[:opening_hours_text])
    assert_includes result[:smoking_hours_text], "水 喫煙不可"
  end

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
      "#{day} 13:00 - 22:00"
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
    assert_equal "both_ok", result[:smoking_type_2]
  end

  test "extracts outside smoking area and later indoor smoking as separate conditions" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      京橋 二刀流
      営業時間
      17:00 - 23:00
      禁煙・喫煙
      分煙
      17時〜21時までは店内禁煙(店外に喫煙所あり)、21時以降店内喫煙可
    TEXT

    assert_equal "separated", result[:smoking_area]
    assert_equal "both_ok", result[:smoking_type]
    assert_equal "all_smoking", result[:smoking_area_2]
    assert_equal "both_ok", result[:smoking_type_2]
    %w[月 火 水 木 金 土 日 祝日].each do |day|
      assert_includes result[:smoking_hours_text], "#{day} 17:00 - 23:00"
    end
  end

  test "extracts smoking at every seat and an outside smoking area separately" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      京屋本店
      営業時間
      月・火・水・木・金・土
      12:00 - 22:00
      日
      定休日
      禁煙・喫煙
      全席喫煙可
      店外に喫煙所あり
    TEXT

    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "both_ok", result[:smoking_type]
    assert_equal "separated", result[:smoking_area_2]
    assert_equal "both_ok", result[:smoking_type_2]
  end

  test "extracts smoking at every seat and a separate bench smoking space" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      ひょうひょう
      禁煙・喫煙
      全席喫煙可
      座席以外に喫煙スペースあり(トイレ前のベンチに灰皿あり)
    TEXT

    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "both_ok", result[:smoking_type]
    assert_equal "separated", result[:smoking_area_2]
    assert_equal "both_ok", result[:smoking_type_2]
  end

  test "extracts smoking at every seat and a smoking area in front of the shop" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      鳥焼肉 四万十家 二郎
      禁煙・喫煙
      全席喫煙可
      お店前にも喫煙所を設置しております
    TEXT

    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "both_ok", result[:smoking_type]
    assert_equal "separated", result[:smoking_area_2]
    assert_equal "both_ok", result[:smoking_type_2]
  end

  test "extracts heated tobacco seating and paper tobacco at the entrance separately" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      +Santsubo
      禁煙・喫煙
      分煙（加熱式たばこ限定）
      紙たばこは店の入り口で喫煙可
    TEXT

    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "electronic_only", result[:smoking_type]
    assert_equal "separated", result[:smoking_area_2]
    assert_equal "both_ok", result[:smoking_type_2]
  end

  test "extracts heated tobacco seating and a paper tobacco booth separately" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      プロント OBP店
      禁煙・喫煙
      分煙（加熱式たばこ限定）
      紙たばこ喫煙ブースあり
    TEXT

    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "electronic_only", result[:smoking_type]
    assert_equal "separated", result[:smoking_area_2]
    assert_equal "both_ok", result[:smoking_type_2]
  end

  test "extracts heated tobacco seating and a paper tobacco smoking room separately" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      大衆ホルモン・やきにく 煙力 京阪京橋店
      禁煙・喫煙
      分煙（加熱式たばこ限定）
      席では加熱式たばこ限定。喫煙ルームで紙たばこ喫煙可
    TEXT

    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "electronic_only", result[:smoking_type]
    assert_equal "separated", result[:smoking_area_2]
    assert_equal "both_ok", result[:smoking_type_2]
  end

  test "treats an outside ashtray as one smoking area for both tobacco types" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      MM GRILL＆CAFE Meat＆Meets
      禁煙・喫煙
      分煙
      店内禁煙、外に灰皿をご用意しております
    TEXT

    assert_equal "separated", result[:smoking_area]
    assert_equal "both_ok", result[:smoking_type]
    assert_nil result[:smoking_area_2]
    assert_nil result[:smoking_type_2]
  end

  test "treats an unqualified smoking room as available to both tobacco types" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      プロント あべの橋駅店
      禁煙・喫煙
      分煙
      喫煙専用室あり
    TEXT

    assert_equal "separated", result[:smoking_area]
    assert_equal "both_ok", result[:smoking_type]
    assert_nil result[:smoking_area_2]
    assert_nil result[:smoking_type_2]
  end

  test "treats terrace-only smoking as seat smoking for both tobacco types" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      テラスカフェバー
      禁煙・喫煙
      分煙
      テラス席のみ喫煙可能
    TEXT

    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "both_ok", result[:smoking_type]
    assert_nil result[:smoking_area_2]
    assert_nil result[:smoking_type_2]
  end

  test "treats smoking allowed on one floor as seat smoking for both tobacco types" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      とりなべ亭 寺田町店
      禁煙・喫煙
      分煙
      1階禁煙、2階喫煙可
    TEXT

    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "both_ok", result[:smoking_type]
    assert_nil result[:smoking_area_2]
    assert_nil result[:smoking_type_2]
  end

  test "extracts heated tobacco indoors and paper tobacco on a balcony separately" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      jazzbar ROOM 335
      禁煙・喫煙
      分煙（加熱式たばこ限定）
      店内加熱式たばこのみ喫煙可紙巻煙草はバルコニーに灰皿設置有
    TEXT

    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "electronic_only", result[:smoking_type]
    assert_equal "separated", result[:smoking_area_2]
    assert_equal "both_ok", result[:smoking_type_2]
  end

  test "extracts an indoor smoking space and smoking seats separately" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      えべっさん
      禁煙・喫煙
      分煙
      店内に喫煙スペースあり／喫煙席：30席
    TEXT

    assert_equal "separated", result[:smoking_area]
    assert_equal "both_ok", result[:smoking_type]
    assert_equal "all_smoking", result[:smoking_area_2]
    assert_equal "both_ok", result[:smoking_type_2]
  end

  test "extracts smoking at counter seats and a table smoking booth separately" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      八千代きっちん はは
      禁煙・喫煙
      分煙
      カウンターのみ喫煙可。 テーブル席は店内に喫煙ブースあり。
    TEXT

    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "both_ok", result[:smoking_type]
    assert_equal "separated", result[:smoking_area_2]
    assert_equal "both_ok", result[:smoking_type_2]
  end

  test "extracts heated tobacco at every seat and paper tobacco at an outside ashtray" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      暦
      禁煙・喫煙
      分煙（加熱式たばこ限定）
      加熱式タバコのみ、全席喫煙可能です。　紙巻タバコの方は、外に灰皿がございます。
    TEXT

    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "electronic_only", result[:smoking_type]
    assert_equal "separated", result[:smoking_area_2]
    assert_equal "both_ok", result[:smoking_type_2]
  end

  test "starts smoking hours after an until-time non-smoking rule for overnight hours" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      こがらや 福島店
      営業時間
      11:00 - 06:00
      禁煙・喫煙
      分煙
      ～13:00まで完全禁煙
    TEXT

    %w[月 火 水 木 金 土 日 祝日].each do |day|
      assert_includes result[:smoking_hours_text], "#{day} 13:00 - 06:00"
      refute_includes result[:smoking_hours_text], "#{day} 11:00 - 06:00"
    end
  end

  test "does not reverse smoking hours when non-smoking-until and smoking-after are both written" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      YAKITORI PLANET
      営業時間
      月・水・木・金・土・日・祝日・祝前日・祝後日
      18:00 - 03:00
      火
      定休日
      禁煙・喫煙
      分煙
      21時まで禁煙/21時以降喫煙可能
    TEXT

    %w[月 水 木 金 土 日 祝日 祝前 祝後].each do |day|
      assert_includes result[:opening_hours_text], "#{day} 18:00-03:00（喫煙可：21:00-03:00）"
      assert_includes result[:smoking_hours_text], "#{day} 21:00 - 03:00"
      refute_includes result[:opening_hours_text], "#{day} 18:00-03:00（喫煙可：18:00-21:00）"
    end
  end

  test "treats a time range followed by wa as a non-smoking lunch period" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      串かつ 五右衛門
      営業時間
      月・火・水・木・金
      11:30 - 13:30
      18:00 - 22:00
      土
      18:00 - 22:00
      日・祝日
      定休日
      禁煙・喫煙
      分煙
      11:30～13:30は全面禁煙
    TEXT

    %w[月 火 水 木 金 土].each do |day|
      assert_includes result[:smoking_hours_text], "#{day} 18:00 - 22:00"
      refute_includes result[:smoking_hours_text], "#{day} 11:30 - 13:30"
    end
    refute_includes result[:smoking_hours_text], "日"
    refute_includes result[:smoking_hours_text], "祝日"
  end

  test "parses morning closing hours and bracketed smoking cutoff" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      自分酒場 大人のフードコート 福島店
      営業時間
      【12:00〜18:00】
      かき氷専門店TIME
      【18:00〜朝4:00】
      BAR TIME
      ■ 定休日
      不定休
      禁煙・喫煙
      分煙
      【〜19時】喫煙不可【19時〜】喫煙可
    TEXT

    %w[月 火 水 木 金 土 日 祝日].each do |day|
      assert_includes result[:opening_hours_text], "#{day} 12:00-18:00, 18:00-28:00"
      assert_includes result[:smoking_hours_text], "#{day} 19:00 - 28:00"
      refute_includes result[:smoking_hours_text], "#{day} 12:00 - 18:00"
    end
    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "both_ok", result[:smoking_type]
  end

  test "subtracts a middle non-smoking period from each day opening hours" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      心斎橋ミツヤ あべちか店
      営業時間
      月・火・水・木・金
      07:00 - 22:00
      土・日・祝日
      08:00 - 22:00
      ■ 定休日
      不定休
      禁煙・喫煙
      分煙
      11時〜18時 全面禁煙
    TEXT

    %w[月 火 水 木 金].each do |day|
      assert_includes result[:smoking_hours_text], "#{day} 07:00 - 11:00, 18:00 - 22:00"
    end
    %w[土 日 祝日].each do |day|
      assert_includes result[:smoking_hours_text], "#{day} 08:00 - 11:00, 18:00 - 22:00"
    end
  end

  test "treats a smoking space that also accepts paper tobacco as available to both types" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      焼肉食べ放題 焼肉クラブ 天王寺店
      禁煙・喫煙
      全席喫煙可
      ※喫煙の場合、加熱式たばこ限定です。 お席で吸えます！！紙たばこも喫煙スペース有り！
    TEXT

    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "electronic_only", result[:smoking_type]
    assert_equal "separated", result[:smoking_area_2]
    assert_equal "both_ok", result[:smoking_type_2]
  end

  test "parses a non-smoking time range written in parentheses" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      らーめん 熊五郎 アポロ店
      営業時間
      11:00 - 22:00
      L.O. 21:30
      ■ 定休日
      無休（元旦休）
      禁煙・喫煙
      分煙
      時間帯禁煙（11：00〜14：00）
    TEXT

    %w[月 火 水 木 金 土 日 祝日].each do |day|
      assert_includes result[:smoking_hours_text], "#{day} 14:00 - 22:00"
      refute_includes result[:smoking_hours_text], "#{day} 11:00 - 22:00"
    end
    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "both_ok", result[:smoking_type]
  end

  test "subtracts a range described as only non-smoking from split opening hours" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      麺屋 志 （メンヤ ココロザシ）
      営業時間
      月・火・木・金
      11:00 - 14:00
      18:00 - 02:00
      土・日・祝日
      11:00 - 15:00
      18:00 - 02:00
      水
      定休日
      禁煙・喫煙
      全席喫煙可
      11:00～13:00のみ禁煙
    TEXT

    %w[月 火 木 金].each do |day|
      assert_includes result[:smoking_hours_text], "#{day} 13:00 - 02:00"
    end
    %w[土 日 祝日].each do |day|
      assert_includes result[:smoking_hours_text], "#{day} 13:00 - 02:00"
    end
    refute_includes result[:smoking_hours_text], "水 "
  end

  test "converts a daytime hour cutoff to 24-hour smoking hours" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      冨士屋 あべちか店
      営業時間
      11:00 - 21:00
      L.O. 20:50
      禁煙・喫煙
      分煙
      昼2時まで禁煙
    TEXT

    %w[月 火 水 木 金 土 日 祝日].each do |day|
      assert_includes result[:smoking_hours_text], "#{day} 14:00 - 21:00"
      refute_includes result[:smoking_hours_text], "#{day} 11:00 - 21:00"
    end
    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "both_ok", result[:smoking_type]
  end

  test "adds an outside smoking space when heated tobacco is limited indoors" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      dasiyaふぁ～る
      禁煙・喫煙
      分煙（加熱式たばこ限定）
      外に喫煙スペース有り
    TEXT

    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "electronic_only", result[:smoking_type]
    assert_equal "separated", result[:smoking_area_2]
    assert_equal "both_ok", result[:smoking_type_2]
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
  test "imports smoking windows before and after a midday ban into advanced settings" do
    result = TabelogPasteParser.call(<<~TEXT)
      店名
      お食事カフェ asahi
      営業時間
      月・火・水・木・金・土
      07:00 - 15:00
      17:30 - 21:00
      日・祝日
      定休日
      禁煙・喫煙
      全席喫煙可
      11:00～12:30まで完全禁煙
      駐車場
      無
    TEXT
    expected = "月 07:00 - 11:00, 12:30 - 15:00, 17:30 - 21:00"
    assert_includes result[:smoking_hours_text], expected
    assert_equal result[:smoking_hours_text], result.dig(:smoking_condition_schedules, "primary", "hours_text")
    assert_equal "custom", result.dig(:smoking_condition_schedules, "primary", "mode")
    assert_includes result[:opening_hours_text], "07:00-15:00（喫煙可：07:00-11:00, 12:30-15:00）"
    shop = Shop.new(result.except(:import_metadata, :raw_import_text, :import_source, :imported_at))
    shop.assign_attributes(address: "大阪府大阪市西区九条南2-34-9", last_confirmed_on: Date.current, genre: "cafe")
    assert shop.valid?, shop.errors.full_messages.join(", ")
    { "07:00" => true, "10:59" => true, "11:00" => false, "12:29" => false,
      "12:30" => true, "15:00" => false, "17:29" => false, "17:30" => true, "21:00" => false }.each do |clock, allowed|
      travel_to(Time.zone.parse("2026-10-26 #{clock}")) { assert_equal allowed, shop.smoking_now?, clock }
    end
    travel_to(Time.zone.parse("2026-11-01 13:00")) { refute shop.smoking_now? }
  end

  test "night smoking without a defined evening start imports unknown timing" do
    result = TabelogPasteParser.call("店名\n福城\n営業時間\n11:00 - 22:00\n禁煙・喫煙\n全席喫煙可\n夜は喫煙可\n駐車場\n無")
    assert_equal "all_smoking", result[:smoking_area]
    assert_equal "both_ok", result[:smoking_type]
    assert_nil result[:smoking_hours_text]
    assert_nil result[:smoking_condition_schedules]
    refute_includes result[:opening_hours_text], "喫煙可："
    shop = Shop.new(result.except(:import_metadata, :raw_import_text, :import_source, :imported_at))
    assert shop.smoking_hours_unset_with_restriction?
    refute shop.advanced_smoking_schedules?
    travel_to(Time.zone.parse("2026-10-26 19:00")) { refute shop.smoking_now? }
  end

end
