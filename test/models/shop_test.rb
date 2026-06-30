require "test_helper"

class ShopTest < ActiveSupport::TestCase
  test "sends aicoo activity when shop is created" do
    with_aicoo_activity_stub do |calls|
      shop = Shop.create!(shop_attributes(name: "AICOO連携テスト店舗"))

      payload = calls.last
      assert_equal "suelog", payload[:business_key]
      assert_equal "data_added", payload[:activity_type]
      assert_equal "shop", payload[:source_type]
      assert_equal shop.id, payload[:source_id]
      assert_includes payload[:title], "店舗を追加"
      assert_equal "梅田", payload[:metadata][:area]
    end
  end

  test "sends aicoo activity when shop is updated" do
    shop = Shop.create!(shop_attributes(name: "AICOO更新前店舗"))

    with_aicoo_activity_stub do |calls|
      shop.update!(phone: "06-1111-2222")

      payload = calls.last
      assert_equal "data_updated", payload[:activity_type]
      assert_equal "shop", payload[:source_type]
      assert_includes payload[:metadata][:changed_fields], "phone"
    end
  end

  test "shop save succeeds when aicoo activity delivery fails" do
    previous_url = ENV["AICOO_API_URL"]
    previous_token = ENV["AICOO_ACTIVITY_API_TOKEN"]
    ENV.delete("AICOO_API_URL")
    ENV.delete("AICOO_ACTIVITY_API_TOKEN")

    assert_nothing_raised do
      Shop.create!(shop_attributes(name: "AICOO送信失敗許容店舗"))
    end
  ensure
    ENV["AICOO_API_URL"] = previous_url
    ENV["AICOO_ACTIVITY_API_TOKEN"] = previous_token
  end

  private

  def shop_attributes(name:)
    {
      name:,
      address: "大阪府大阪市北区梅田1-1-1",
      area: "梅田",
      genre: "居酒屋",
      last_confirmed_on: Date.current,
      source: "test"
    }
  end

  def with_aicoo_activity_stub
    original = AicooActivityLogger.method(:log)
    calls = []
    AicooActivityLogger.define_singleton_method(:log) do |**attributes|
      calls << attributes
      { ok: true }
    end

    yield calls
  ensure
    AicooActivityLogger.define_singleton_method(:log, original)
  end
end
