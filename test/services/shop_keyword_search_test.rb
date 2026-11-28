require "test_helper"

class ShopKeywordSearchTest < ActiveSupport::TestCase
  setup do
    Geocoder.configure(lookup: :test)
    Geocoder::Lookup::Test.set_default_stub([])
  end

  test "normalizes width case kana spaces punctuation and documented aliases on both sides" do
    pairs = [["ＤＯＵＴＯＲ ｶﾌｪ", "doutorかふぇ"], ["髙槻 駅前", "高槻駅前"], ["三国ケ丘", "三国が丘"],
      ["なかもず", "中百舌鳥"], ["ナンバ", "難波"], ["焼鳥", "やきとり"], ["０６－１２３４－５６７８", "0612345678"],
      ["Cafe・BOND", "cafe bond"], ["ｶﾞｰﾃﾞﾝ", "がーでん"]]
    pairs.each { |left, right| assert_equal ShopKeywordSearch.normalize(left), ShopKeywordSearch.normalize(right), "#{left} / #{right}" }
    refute_equal ShopKeywordSearch.normalize("カフェ"), ShopKeywordSearch.normalize("カフエ")
    refute_equal ShopKeywordSearch.normalize("バー"), ShopKeywordSearch.normalize("バ")
  end

  test "saved projection is searchable immediately including after edits and validation bypass" do
    shop = create_shop(name: "Ｃａｆｅ ＢＯＮＤ", address: "大阪府大阪市浪速区難波", genre: "カフェ", phone: "0612345678", approved: true)
    %w[cafebond かふぇ なんば ０６－１２３４－５６７８].each { |q| assert_includes Shop.keyword(q).pluck(:id), shop.id }
    shop.update!(nearest_station: "中百舌鳥駅")
    assert_includes ShopKeywordSearch.apply(Shop.all, "なかもず", station: true).pluck(:id), shop.id
    assert_not_includes ShopKeywordSearch.apply(Shop.all, "難波", station: true).pluck(:id), shop.id
    shop.update!(name: "ニュー・カフェ")
    assert_not_includes Shop.keyword("cafebond").pluck(:id), shop.id
    assert_includes Shop.keyword("にゅーかふぇ").pluck(:id), shop.id
    shop.name = "カタカナ"
    shop.save!(validate: false)
    assert_includes Shop.keyword("かたかな").pluck(:id), shop.id
    assert_not_includes Shop.keyword("にゅーかふぇ").pluck(:id), shop.id
  end

  test "wildcard and punctuation only queries never match everything" do
    ordinary = create_shop(name: "通常の店舗", approved: true)
    literal = create_shop(name: "１００％_CAFE", approved: true)
    assert_empty Shop.keyword("%_")
    assert_equal [literal.id], Shop.keyword("１００ＣＡＦＥ").pluck(:id)
    assert_not_includes Shop.keyword("%_").pluck(:id), ordinary.id
    assert_empty Shop.keyword("-")
    assert_equal Shop.count, Shop.keyword("　 ").count
  end

  test "bulk inserted legacy rows remain searchable within the given relation" do
    now = Time.current
    ids = Shop.insert_all!([{ name: "ﾄﾞﾄｰﾙ", address: "中百舌鳥", approved: true, created_at: now, updated_at: now },
      { name: "ドトール非公開", address: "中百舌鳥", approved: false, created_at: now, updated_at: now }]).rows.flatten
    assert_equal [ids.first], Shop.approved.keyword("どとーる").pluck(:id)
    assert_includes Shop.keyword("ナカモズ").pluck(:id), ids.first
    assert_empty Shop.where(id: ids.first).keyword("存在しない")
    assert_not Shop.where(id: ids.first).keyword("どとーる中百舌鳥").exists?, "Matches must not cross field boundaries"
  end
  test "separator forms match store titles and stations without treating punctuation as required" do
    shop = create_shop(name: "立ち寿司ホルモン 新鮮や！", nearest_station: "近鉄日本橋駅", approved: true)
    separators = [" ", "　", "\t", "\n", "｜", "|", "／", "/", "・", "、", ",", "：", ":", "；", ";", "—", "-", "（", "【", "→", "★", "！", "_", "％", "＆", "…", "＝", "＋"]
    separators.each do |separator|
      query = "立ち寿司ホルモン#{separator}新鮮や！#{separator}近鉄日本橋"
      assert_includes Shop.approved.keyword(query).pluck(:id), shop.id, query
    end
    assert_includes Shop.keyword("新鮮や").pluck(:id), shop.id
    assert_includes Shop.keyword("新鮮や!｜近鉄 日本橋").pluck(:id), shop.id
    assert_empty Shop.keyword("新鮮や｜存在しない駅")
    assert_empty Shop.keyword("｜ ／ ★")
    shop.update!(name: "立ち寿司ホルモン｜新鮮や！")
    assert_includes Shop.keyword("立ち寿司ホルモン 新鮮や").pluck(:id), shop.id
  end

  private

  def create_shop(**values)
    Shop.create!({ address: "大阪府大阪市北区梅田1-1", genre: "カフェ", last_confirmed_on: Date.current,
      smoking_area: :all_smoking, smoking_type: :both_ok }.merge(values))
  end

end
