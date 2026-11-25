require "test_helper"

class SeoPageCatalogTest < ActiveSupport::TestCase
  setup do
    Shop.update_all(approved: false, on_hold: false)
    Rails.cache.clear
    @catalog = SeoPageCatalog.new
  end

  test "inventory includes all configured parents and facets with the same sitemap decisions" do
    seed(12, genre: "居酒屋")
    seed(5, genre: "カフェ", smoking_area: 0)
    seed(3, genre: "バー", smoking_type: 1)
    directory = GeographicDirectory.new
    facets = GeographicFacets.new(directory)
    assert_equal (directory.regions.size + directory.stations.size) * (facets.definitions.size + 1), @catalog.rows.size
    facet_rows = @catalog.rows.select { |row| %w[genre smoking].include?(row[:kind]) }
    assert_equal facets.all_published.map { |entry, facet| facets.path(entry, facet) }.sort,
      facet_rows.select { |row| row[:status] == "index" }.map { |row| row[:path] }.sort
    row = find_row("/areas/suita/genre/izakaya")
    assert_equal "index", row[:status]
    assert_equal "eligible", row[:reason]
    assert_equal 12, row[:count]
    assert_equal 20, row[:parent_count]
    duplicate = find_row("/stations/esaka/genre/izakaya")
    assert_equal "noindex", duplicate[:status]
    assert_equal "duplicate", duplicate[:reason]
    assert_equal row[:url], duplicate[:canonical]
    thin = find_row("/areas/suita/genre/cafe")
    assert_equal "insufficient_shops", thin[:reason]
    assert_equal "noindex", thin[:status]
    assert_equal thin[:url], thin[:canonical]
    empty = find_row("/areas/sakai-naka")
    assert_equal "not_found", empty[:status]
    assert_equal "no_shops", empty[:reason]
    assert_nil empty[:canonical]
    assert_equal @catalog.rows.length, @catalog.counts.values_at("index", "noindex", "not_found").sum
  end

  test "near parent reasons come directly from public publication rules" do
    seed(10, genre: "居酒屋")
    seed(1, genre: "カフェ")
    row = find_row("/areas/suita/genre/izakaya")
    assert_equal "near_parent", row[:reason]
    assert_equal "noindex", row[:status]
    assert_equal "https://suelog.jp/areas/suita", row[:canonical]
  end

  test "search filters and numeric sorting work without issuing per page queries" do
    seed(12, genre: "居酒屋")
    seed(5, genre: "カフェ", smoking_area: 0)
    queries = []
    callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] if payload[:sql].match?(/SELECT.*FROM ["`]?shops/i) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      matches = @catalog.search(query: "吹田 居酒屋", kind: "genre", status: "index")
      assert_equal ["/areas/suita/genre/izakaya"], matches.map { |row| row[:path] }
      assert_equal 1, @catalog.search(query: "/stations/esaka/genre/izakaya", reason: "duplicate").size
      assert_empty @catalog.search(query: "存在しない地名")
      ascending = @catalog.search(status: "noindex", sort: "shops_asc").map { |row| row[:count] }
      assert_equal ascending.sort, ascending
      urls = @catalog.search(query: "/areas/suita/", sort: "url").map { |row| row[:path] }
      assert_equal urls.sort, urls
      assert @catalog.counts.fetch("total").positive?
    end
    assert_equal 1, queries.length
    assert_no_match(/SELECT\s+\*/, queries.first)
  end

  private

  def find_row(path)
    @catalog.rows.find { |row| row[:path] == path } || flunk("Missing inventory row: #{path}")
  end

  def seed(count, **values)
    now = Time.current
    Shop.insert_all!(Array.new(count) do |i|
      { name: "SEO店舗#{i}", address: "大阪府吹田市江坂町1-1", nearest_station: "江坂駅から100m",
        genre: "居酒屋", approved: true, on_hold: false, smoking_unverified: false,
        smoking_area: 1, smoking_type: 0, last_confirmed_on: Date.current, created_at: now, updated_at: now }.merge(values)
    end)
  end
end
