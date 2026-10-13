require "test_helper"

class ShopsHelperTest < ActionView::TestCase
  test "short station label chooses shortest stated walking time" do
    assert_equal "中津駅 徒歩3分", compact_station_label("阪急線 梅田駅 徒歩5分 地下鉄御堂筋線中津駅より徒歩3分 梅田駅から398m")
    assert_equal "梅田駅 徒歩5分", compact_station_label("大阪メトロ 御堂筋線「梅田」駅 徒歩９分 中崎町駅から411m 阪神本線梅田駅徒歩5分")
  end

  test "distances are compared in the same unit" do
    assert_equal "梅田駅から398m", compact_station_label("大阪駅から0.8km 梅田駅から398m")
  end

  test "station names and unparseable text remain useful" do
    assert_equal "梅田駅", compact_station_label("阪急線 梅田駅・大阪駅")
    assert_equal "アクセス情報を確認中", compact_station_label("アクセス情報を確認中")
    assert_nil compact_station_label(nil)
  end
end
