require "test_helper"

class TabelogPasteParserTest < ActiveSupport::TestCase
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
    assert_equal "paper_only", result[:smoking_type_2]
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
    assert_equal "paper_only", result[:smoking_type_2]
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
    assert_equal "paper_only", result[:smoking_type_2]
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
    assert_equal "paper_only", result[:smoking_type_2]
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
    assert_equal "paper_only", result[:smoking_type_2]
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
    assert_equal "paper_only", result[:smoking_type_2]
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
end
