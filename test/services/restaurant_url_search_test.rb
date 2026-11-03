require "test_helper"

class RestaurantUrlSearchTest < ActiveSupport::TestCase
  FakeShop = Struct.new(:name, :address, :phone, keyword_init: true)
  class Client
    attr_reader :calls
    def initialize(results = [], site: false, available: true)
      @results, @site, @available, @calls = results.dup, site, available, []
    end
    def available? = @available
    def supports_site_search? = @site
    def search(query)
      @calls << query
      @results.shift || []
    end
    def site_search(provider, name)
      @calls << [provider, name]
      @results.shift || []
    end
  end
  class Reader
    attr_reader :calls
    def initialize(evidence)
      @evidence, @calls = evidence, []
    end
    def call(url, _provider)
      @calls << url
      @evidence[url]
    end
  end

  setup do
    @shop = FakeShop.new(name: "Ｃａｆｅ　Ａ 梅田店", address: "大阪府大阪市北区梅田１丁目２番３号 梅田ビル２階", phone: "０６－１２３４－５６７８")
    @url = "https://r.gnavi.co.jp/abcd123/"
    @evidence = { name: "Cafe A 梅田店", address: "大阪市北区梅田1-2-3 梅田ビル2F", phone: "0612345678" }
  end

  test "first query has municipality without street or building and stops after a verified match" do
    client = Client.new([[{"link"=>@url}]])
    result = RestaurantUrlSearch::Search.new(@shop, "gurunavi", client: client, reader: Reader.new(@url => @evidence)).call
    assert_equal "matched", result[:state]
    assert_equal @url, result[:url]
    assert_equal ["Ｃａｆｅ　Ａ 梅田店 大阪市北区 site:r.gnavi.co.jp"], client.calls
    assert_not_includes client.calls.first, "ビル"
  end

  test "falls back to hyphenated then digit phone queries and stops on a match" do
    client = Client.new([[], [], [{"link"=>@url}]])
    result = RestaurantUrlSearch::Search.new(@shop, "gurunavi", client: client, reader: Reader.new(@url=>@evidence)).call
    assert_equal "matched", result[:state]
    assert_equal ["name_city", "phone", "phone"], result[:queries].map { |q| q[:stage] }
    assert_equal ["06-1234-5678 site:r.gnavi.co.jp", "0612345678 site:r.gnavi.co.jp"], client.calls.last(2)
  end

  test "missing phone skips phone queries and unavailable site integration leaves unconfirmed" do
    @shop.phone = nil
    client = Client.new
    result = RestaurantUrlSearch::Search.new(@shop, "gurunavi", client: client, reader: Reader.new({})).call
    assert_equal "review", result[:state]
    assert_equal 1, client.calls.size
    assert_includes result[:reason], "未連携"
    assert_nil result[:url]
    matching = Client.new([[{"link"=>@url}]])
    assert_equal "matched", RestaurantUrlSearch::Search.new(@shop, "gurunavi", client: matching, reader: Reader.new(@url=>@evidence.merge(phone: nil))).call[:state]
  end

  test "native search is called only when an integration supports it" do
    @shop.phone = nil
    client = Client.new([[], [{"link"=>@url}]], site: true)
    result = RestaurantUrlSearch::Search.new(@shop, "gurunavi", client: client, reader: Reader.new(@url=>@evidence)).call
    assert_equal "matched", result[:state]
    assert_equal ["gurunavi", @shop.name], client.calls.last
    assert_equal "site", result[:queries].last[:stage]
  end

  test "similar name other branch conflicting phone floor and relocation are not accepted" do
    [@evidence.merge(name: "Cafe A 難波店"), @evidence.merge(name: "Cafe A 梅田店 別館"),
      @evidence.merge(phone: "06-9999-9999"), @evidence.merge(address: "大阪市北区梅田1-2-4 梅田ビル2F"),
      @evidence.merge(address: "大阪市北区梅田1-2-3 梅田ビル3F"), @evidence.merge(relocated: true),
      @evidence.merge(address: nil), @evidence.merge(phone: nil)].each do |evidence|
      matched, = RestaurantUrlSearch::CandidateMatcher.call(@shop, evidence)
      assert_not matched, evidence.inspect
    end
  end

  test "never adopts the first result blindly and refuses multiple verified URLs" do
    other = "https://r.gnavi.co.jp/other123/"
    client = Client.new([[{"link"=>other}, {"link"=>@url}]])
    reader = Reader.new(other=>@evidence.merge(name: "Cafe A 難波店"), @url=>@evidence)
    assert_equal @url, RestaurantUrlSearch::Search.new(@shop, "gurunavi", client: client, reader: reader).call[:url]
    client = Client.new([[{"link"=>other}, {"link"=>@url}]])
    result = RestaurantUrlSearch::Search.new(@shop, "gurunavi", client: client, reader: Reader.new(other=>@evidence, @url=>@evidence)).call
    assert_equal "review", result[:state]
    assert_nil result[:url]
  end

  test "search listing wrong host malformed URL and menu pages are never candidates" do
    provider = RestaurantUrlSearch::Provider.new("hotpepper")
    assert_equal "https://www.hotpepper.jp/strJ001234567/", provider.canonical_url("http://hotpepper.jp/strJ001234567/?vos=123")
    ["https://www.hotpepper.jp/SA23/", "https://www.hotpepper.jp/strJ001234567/food/", "https://beauty.hotpepper.jp/strJ001234567/", "https://www.hotpepper.jp.evil.test/strJ001234567/", "javascript:alert(1)"].each do |url|
      assert_nil provider.canonical_url(url)
    end
    @shop.phone = nil
    reader = Reader.new({})
    result = RestaurantUrlSearch::Search.new(@shop, "gurunavi", client: Client.new([[{"link"=>"https://r.gnavi.co.jp/area/osaka/"}]]), reader: reader).call
    assert_empty result[:candidates]
    assert_empty reader.calls
    assert_equal "review", result[:state]
  end

  test "API absent is unavailable rather than not listed" do
    result = RestaurantUrlSearch::Search.new(@shop, "gurunavi", client: Client.new(available: false)).call
    assert_equal "unavailable", result[:state]
    assert_empty result[:queries]
  end

  test "municipalities and phone variants normalize without adding street numbers" do
    n = RestaurantUrlSearch::Normalization
    { "三重県四日市市諏訪町1-1"=>"四日市市", "東京都新宿区西新宿1-1"=>"新宿区", "〒530-0001 大阪府大阪市北区梅田1-2"=>"大阪市北区", "神奈川県横浜市港北区日吉1-1"=>"横浜市港北区", "大阪府三島郡島本町広瀬1-1"=>"三島郡島本町" }.each do |address, expected|
      assert_equal expected, n.municipality(address)
    end
    @shop.phone = "0612345678"
    queries = n.queries(@shop, RestaurantUrlSearch::Provider.new("gurunavi"))
    assert_equal "06-1234-5678 site:r.gnavi.co.jp", queries.last[:query]
    assert_raises(ArgumentError) { RestaurantUrlSearch::Provider.new("tabelog") }
  end

  test "detail reader uses structured store evidence and flags former locations" do
    body = '<main><script type="application/ld+json">{"@type":"Restaurant","url":"https://r.gnavi.co.jp/abcd123/","name":"Cafe A 梅田店","address":{"addressRegion":"大阪府","addressLocality":"大阪市北区","streetAddress":"梅田1-2-3 梅田ビル2F"},"telephone":"06-1234-5678"}</script>移転しました</main>'
    evidence = RestaurantUrlSearch::DetailReader.new.parse(body, @url, RestaurantUrlSearch::Provider.new("gurunavi"))
    assert_equal "Cafe A 梅田店", evidence[:name]
    assert_equal "大阪府大阪市北区梅田1-2-3 梅田ビル2F", evidence[:address]
    assert evidence[:relocated]
  end
end
