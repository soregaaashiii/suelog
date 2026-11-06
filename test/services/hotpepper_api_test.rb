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
end
