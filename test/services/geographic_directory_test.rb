require "test_helper"

class GeographicDirectoryTest < ActiveSupport::TestCase
  setup do
    Shop.update_all(approved: false, on_hold: false)
    Rails.cache.clear
    @directory = GeographicDirectory.new
  end

  test "municipality boundaries reject another prefecture and preserve city and ward distinctions" do
    assert_equal "suita", @directory.region_key(" 大阪府 吹田市江坂町1-2-3")
    assert_equal "sakai-sakai", @directory.region_key("堺市堺区三国ヶ丘1-1")
    assert_equal "osaka-tennoji", @directory.region_key("大阪府大阪市天王寺区堀越町1-1")
    assert_nil @directory.region_key("京都府京都市下京区四条町")
    assert_nil @directory.region_key("")
  end

  test "uses the final station statement and not a similar name or a station mentioned in directions" do
    assert_equal "esaka", @directory.station_key("地下鉄江坂駅 徒歩3分\n江坂駅から118m", "suita")
    assert_equal "shin-osaka", @directory.station_key("大阪駅から電車で5分\n新大阪駅から200m", "osaka-yodogawa")
    assert_nil @directory.station_key("南江坂駅から118m", "suita")
    assert_nil @directory.station_key("江坂駅から118m", "toyonaka")
    assert_nil @directory.station_key("豊中駅から118m", "suita")
    assert_nil @directory.station_key("江坂駅徒歩3分から新大阪駅方面", "suita")
    assert_nil @directory.station_key("平野駅から100m", "osaka-hirano"), "distant JR/metro stations with an ambiguous shared name are deferred"
  end

  test "retains parenthetical lines and explicit interchange spelling variants" do
    assert_equal "nakamozu", @directory.station_key("なかもず駅（大阪メトロ）から77m", "sakai-kita")
    assert_equal "nakamozu", @directory.station_key("中百舌鳥駅から８０m", "sakai-kita")
    assert_equal "esaka", @directory.station_key("江坂駅", "suita")
  end

  test "counts and listing scopes agree without duplicates and enforce the publication threshold" do
    10.times { |i| insert_shop(name: "江坂#{i}", address: "大阪府吹田市江坂町1-#{i}", nearest_station: "江坂駅から#{i + 100}m") }
    insert_shop(name: "別地域の同名駅", address: "京都府京都市下京区1-1", nearest_station: "江坂駅から100m")
    insert_shop(name: "未承認", approved: false)
    insert_shop(name: "保留", on_hold: true)
    entry = @directory.definition("station", "esaka")
    assert_equal 10, @directory.stats(entry).fetch("count")
    assert_equal 10, @directory.scope(entry).count
    assert @directory.published?(entry)
    assert_equal 10, @directory.stats(entry).fetch("genres").fetch("居酒屋")
    Shop.where(name: "江坂0").update_all(approved: false)
    assert_equal 9, @directory.scope(entry).count, "cached station IDs never expose newly private shops"
    Rails.cache.clear
    refreshed = GeographicDirectory.new
    assert_not refreshed.published?(entry)
  end

  test "catalog reads scalar fields with one query instead of one query per area or station" do
    insert_shop
    queries = []
    subscriber = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] if payload[:sql].match?(/SELECT.*FROM ["`]?shops/i) }
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      @directory.published("region")
      @directory.published("station")
    end
    assert_equal 1, queries.length
    assert_no_match(/SELECT\s+\*/, queries.first)
  end

  private

  def insert_shop(**overrides)
    now = Time.current
    Shop.insert_all!([{ name: "地域店舗", address: "大阪府吹田市江坂町1-1", nearest_station: "江坂駅から100m",
      genre: "居酒屋", approved: true, on_hold: false, rejected: false,
      smoking_area: 1, smoking_type: 0, last_confirmed_on: Date.current,
      created_at: now, updated_at: now }.merge(overrides)])
  end
end
