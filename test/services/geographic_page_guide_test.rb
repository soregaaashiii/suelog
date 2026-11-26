require "test_helper"
require_relative "../support/search_console_test_helpers"

class GeographicPageGuideTest < ActiveSupport::TestCase
  include SearchConsoleTestHelpers
  setup { seed_gsc_catalog }

  test "condition counts are intersections with the selected page not the whole parent" do
    guide = build_guide("region", "suita", "genre", "izakaya")
    assert_match(/掲載20件のうち.*12件/, guide.overview)
    assert_equal [12, 0, 0], guide.conditions.map { |r| r[:count] }
    assert_equal 15, guide.conditions.first[:destination_count]
    assert_equal "/areas/suita/smoking/seat-smoking", guide.conditions.first[:path]
    assert_empty guide.other_stations
    seat = build_guide("region", "suita", "smoking", "seat-smoking")
    assert_equal 15, seat.conditions.first[:count]
    assert_nil seat.conditions.first[:path]
    assert_equal [{ label: "居酒屋", count: 12, path: "/areas/suita/genre/izakaya", destination_count: 12 }], seat.genre_links
  end

  test "unverified conditions are not counted and no unpublished condition links are introduced" do
    Shop.where(genre: "居酒屋").update_all(smoking_unverified: true)
    Rails.cache.clear
    guide = build_guide("region", "suita")
    assert_match(/20件/, guide.overview)
    assert_equal [3, 5, 0], guide.conditions.map { |r| r[:count] }
    assert guide.conditions.all? { |r| r[:path].nil? }
  end

  test "station links use the same municipality published pages and preserve eligible facets" do
    add_station("天満駅", 20, 12)
    add_station("扇町駅", 15, 10)
    add_station("天神橋筋六丁目駅", 10, 10)
    add_station("大阪天満宮駅", 1, 1)
    add_station("淀屋橋駅", 15, 10)
    Shop.where("name LIKE ?", "淀屋橋駅%").update_all(address: "大阪府大阪市中央区北浜1-1")
    Rails.cache.clear
    guide = build_guide("station", "temma", "genre", "izakaya")
    assert_equal ["/stations/ogimachi/genre/izakaya", "/stations/tenjinbashisuji-6chome"], guide.other_stations.map { |r| r[:path] }
    assert_equal [10, 10], guide.other_stations.map { |r| r[:count] }
    assert guide.other_stations.none? { |r| r[:path].include?("esaka") || r[:path].include?("osaka-temmangu") }
    base = build_guide("station", "temma")
    assert_match(/天満駅が登録された最寄駅/, base.overview)
    assert base.other_stations.all? { |r| !r[:path].include?("/genre/") }
  end

  test "guide uses the existing cached snapshot with no additional database queries" do
    directory = GeographicDirectory.new
    directory.statistics
    facets = GeographicFacets.new(directory)
    guide = GeographicPageGuide.new(directory: directory, facets: facets, entry: directory.definition("station", "esaka"))
    queries = []
    callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" || payload[:cached] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      guide.overview
      guide.conditions
      guide.genre_links
      guide.other_stations
    end
    assert_empty queries
  end

  private

  def build_guide(kind, slug, facet_kind = nil, facet_slug = nil)
    directory = GeographicDirectory.new
    facets = GeographicFacets.new(directory)
    GeographicPageGuide.new(directory: directory, facets: facets, entry: directory.definition(kind, slug), facet: facet_kind && facets.definition(facet_kind, facet_slug))
  end

  def add_station(station, count, izakaya)
    now = Time.current
    Shop.insert_all!(Array.new(count) do |i|
      { name: "#{station}#{i}", address: "大阪府大阪市北区天神橋1-1", nearest_station: "#{station}から100m", genre: i < izakaya ? "居酒屋" : "カフェ",
        approved: true, on_hold: false, smoking_unverified: false, smoking_area: 1, smoking_type: 0, created_at: now, updated_at: now }
    end)
  end
end
