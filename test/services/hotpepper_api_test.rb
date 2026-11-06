require "test_helper"

class HotpepperApiTest < ActiveSupport::TestCase
  class Client < RestaurantUrlSearch::HotpepperApi
    attr_reader :requests
    def initialize(shop, records)
      super(shop)
      @records, @requests = records, []
    end
    def fetch(params)
      @requests << params
      @records
    end
  end

  def shop(phone = "0612345678")
    Shop.new(name: "テスト 北店", address: "大阪府大阪市北区梅田1-2-3", phone: phone)
  end

  def records(name: "テスト 北店", address: "大阪府大阪市北区梅田1-2-3")
    [{ "name" => name, "address" => address, "urls" => { "pc" => "https://www.hotpepper.jp/strJ003451218/" } }]
  end

  test "phone fallback confirms identity and returns ordinary URL" do
    client = Client.new(shop, records)
    result = client.call
    assert_equal "matched", result[:state]
    assert_equal 2, client.requests.size
    assert_equal "0612345678", client.requests.last[:tel]
    assert_equal "https://www.hotpepper.jp/strJ003451218/", result[:url]
  end

  test "missing phone still supports name and address matching" do
    client = Client.new(shop(nil), records)
    assert_equal "matched", client.call[:state]
    assert_equal 1, client.requests.size
  end

  test "different branch or floor is not confirmed" do
    assert_equal "review", Client.new(shop, records(name: "テスト 南店")).call[:state]
    assert_equal "review", Client.new(shop, records(address: "大阪府大阪市北区梅田1-2-3 2F")).call[:state]
  end

  test "no results remain unconfirmed" do
    assert_equal "review", Client.new(shop, []).call[:state]
  end
  class PagedClient < RestaurantUrlSearch::HotpepperApi
    attr_reader :requests
    def initialize(shop, pages)
      super(shop)
      @pages, @requests = pages, []
    end
    def fetch_page(params)
      @requests << params
      @pages.fetch(params.fetch(:start, 1))
    end
  end

  test "bulk candidate search retrieves later API pages before matching" do
    pages = {
      1 => { "results_available" => 101, "shop" => [{ "id" => "J000000001", "name" => "別店", "address" => "大阪府大阪市北区梅田9-9-9" }] },
      101 => { "results_available" => 101, "shop" => records.map { |row| row.merge("id" => "J003451218") } }
    }
    client = PagedClient.new(shop, pages)
    found = client.records_for_matching
    assert_equal 2, found.size
    assert_equal [1, 101], client.requests.map { |params| params[:start] }
  end

  test "truncated broad query is never treated as an exhaustive candidate set" do
    client = PagedClient.new(shop, {1 => { "results_available" => 1001, "shop" => records }})
    assert_raises(RestaurantUrlSearch::HotpepperApi::TooManyCandidates) { client.records_for_matching }
  end

end
