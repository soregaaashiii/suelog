require "test_helper"

class SharedGenreOptionsTest < ActionDispatch::IntegrationTest
  setup do
    Geocoder.configure(lookup: :test)
    Geocoder::Lookup::Test.set_default_stub([])
    Shop.update_all(approved: false, on_hold: false)
    @shop = Shop.create!(name: "ジャンル共通化店舗", address: "大阪市北区梅田1", area: "梅田",
      genre: "その他", genre_other: "レコードバー／ダーツバー、カフェ・レコードバー",
      approved: true, latitude: 34.7, longitude: 135.5,
      last_confirmed_on: Date.current, smoking_area: "all_smoking", smoking_type: "both_ok")
    Shop.create!(name: "非公開店舗", address: "大阪市北区梅田2", genre: "その他",
      genre_other: "審査中ジャンル", last_confirmed_on: Date.current)
  end

  test "all public selectors share standard and approved custom genres in map order" do
    expected = (Shop::GENRES.reject { |value| value == "その他" } + [ "レコードバー", "ダーツバー" ]).uniq.sort + [ "その他" ]
    assert_equal expected, Shop.selectable_genre_options
    assert_not_includes Shop.genre_options, "レコードバー" # Parser's standard vocabulary stays fixed.
    [ [ root_path, "genre" ], [ umeda_path, "genre" ], [ "/map", "map-genre" ],
      [ new_shop_path, "shop_genre" ], [ new_shop_shop_edit_request_path(@shop), "shop_edit_request_genre" ] ].each do |path, id|
      get path
      assert_response :success
      values = css_select("select##{id} option").map { |option| option["value"].to_s.delete_prefix("custom_genre:") }.reject(&:blank?)
      assert_equal expected, values, path
    end
  end

  test "each separator supported by the map also works in home genre search" do
    [ "、", ",", "，", "/", "／", "｜", "|", "・" ].each do |separator|
      @shop.update!(genre_other: "レコードバー#{separator}ダーツバー")
      get root_path, params: { genre: "ダーツバー" }
      assert_response :success
      assert_select ".shop-card__titleLink", text: @shop.name
    end
  end

  test "registration stores selected custom genre instead of stale other text" do
    assert_difference "Shop.count", 1 do
      post shops_path, params: { shop: { name: "追加ジャンル登録", address: "大阪市北区梅田3",
        genre: "custom_genre:レコードバー", genre_other: "以前の入力", last_confirmed_on: Date.current,
        smoking_area: "all_smoking", smoking_type: "both_ok" } }
    end
    assert_response :redirect
    shop = Shop.order(:id).last
    assert_equal "その他", shop.genre
    assert_equal "レコードバー", shop.genre_other
    assert_not shop.approved?
  end

  test "custom genre labels that match legacy aliases retain their exact label" do
    @shop.update!(genre_other: "カフェバー")
    assert_includes Shop.genre_form_options, [ "カフェバー", "custom_genre:カフェバー" ]
    @shop.update!(genre: "custom_genre:カフェバー", genre_other: "古い入力")
    assert_equal "その他", @shop.genre
    assert_equal "カフェバー", @shop.genre_other
  end

  test "edit request preserves selected custom genre for approval" do
    request = @shop.shop_edit_requests.create!(genre: "custom_genre:ダーツバー", genre_other: "以前の入力",
      proposed_smoking_area: "area_all_smoking", proposed_smoking_type: "type_both_ok")
    assert_equal "その他", request.genre
    assert_equal "ダーツバー", request.genre_other
  end
end
