require "test_helper"

class GeographicFacetsTest < ActiveSupport::TestCase
  setup do
    Shop.update_all(approved: false, on_hold: false)
    Rails.cache.clear
    @directory = GeographicDirectory.new
    @facets = GeographicFacets.new(@directory)
    @region = @directory.definition("region", "suita")
  end

  test "genre token counts match live listing queries including aliases and custom genres" do
    seed(10, genre: "その他", genre_other: "焼き鳥／居酒屋")
    seed(6, genre: "カフェ")
    seed(1, genre: "ダイニングバー")
    yakitori = @facets.definition("genre", "yakitori")
    bar = @facets.definition("genre", "bar")
    assert_equal 10, @facets.stats(@region, yakitori).fetch("count")
    assert_equal 10, @facets.scope(@region, yakitori).count
    assert_equal 0, @facets.stats(@region, bar).fetch("count"), "bar must not match dining-bar as a substring"
    assert_includes @facets.published(@region).map { |f| f.fetch("slug") }, "izakaya"
    assert_not_includes @facets.published(@region).map { |f| f.fetch("slug") }, "yakitori", "identical shop sets only publish once"
  end

  test "thin and near-duplicate subsets are not published" do
    seed(10, genre: "居酒屋")
    seed(1, genre: "カフェ")
    facet = @facets.definition("genre", "izakaya")
    assert_not @facets.decision(@region, facet).fetch(:published)
    assert_equal "/areas/suita", @facets.decision(@region, facet).fetch(:canonical)
    assert_not @facets.decision(@region, @facets.definition("genre", "cafe")).fetch(:published)
  end

  test "identical station and region subsets canonicalize to one geographic genre URL" do
    seed(10, genre: "居酒屋")
    seed(6, genre: "カフェ")
    facet = @facets.definition("genre", "izakaya")
    station = @directory.definition("station", "esaka")
    assert @facets.decision(@region, facet).fetch(:published)
    assert_not @facets.decision(station, facet).fetch(:published)
    assert_equal "/areas/suita/genre/izakaya", @facets.decision(station, facet).fetch(:canonical)
  end

  test "smoking facets honor advanced secondary conditions and restrictions without claiming current availability" do
    row = { smoking_area: "all_smoking", smoking_type: "electronic_only", smoking_unverified: false,
      smoking_area_2: "separated", smoking_type_2: "both_ok",
      smoking_condition_schedules: { "primary" => { "mode" => "custom", "hours_text" => "月〜金 15:00〜21:00" }, "secondary" => { "mode" => "business" } } }
    assert_equal %w[smoking/seat-smoking smoking/smoking-room], GeographicFacets.smoking_keys(row)
    assert_equal %w[smoking/seat-smoking smoking/heated-only], GeographicFacets.smoking_keys(row.merge(smoking_condition_schedules: {}))
    assert_empty GeographicFacets.smoking_keys(row.merge(smoking_unverified: true))
    assert_equal ["smoking/smoking-room"], GeographicFacets.smoking_keys(row.merge(smoking_condition_schedules: { "primary" => { "situation_note" => "貸切時のみ" }, "secondary" => { "mode" => "business" } }))
    assert_not_includes GeographicFacets.smoking_keys(row.merge(smoking_type_2: "unknown")), "smoking/heated-only"
  end

  test "smoking listing rechecks edits made after statistics were cached" do
    seed(10, smoking_unverified: false)
    seed(6, smoking_unverified: true)
    facet = @facets.definition("smoking", "seat-smoking")
    assert_equal 10, @facets.stats(@region, facet).fetch("count")
    assert @facets.decision(@region, facet).fetch(:published)
    Shop.where(smoking_unverified: false).update_all(smoking_area: 2)
    assert_equal 0, @facets.scope(@region, facet).count
  end

  private

  def seed(count, **values)
    now = Time.current
    Shop.insert_all!(Array.new(count) do |i|
      { name: "条件店舗#{i}", address: "大阪府吹田市江坂町1-1", nearest_station: "江坂駅から100m",
        genre: "居酒屋", approved: true, on_hold: false, smoking_area: 1, smoking_type: 0,
        last_confirmed_on: Date.current, created_at: now, updated_at: now }.merge(values)
    end)
  end
end
