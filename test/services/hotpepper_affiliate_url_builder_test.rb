require "test_helper"

class HotpepperAffiliateUrlBuilderTest < ActiveSupport::TestCase
  test "matches the supplied ValueCommerce example and replaces existing campaign parameters" do
    template = HotpepperAffiliateUrlBuilder::DEFAULT_TEMPLATE
    target = "https://www.hotpepper.jp/strJ003451218/?vos=nhppvccp99002"
    expected = "https://ck.jp.ap.valuecommerce.com/servlet/referral?sid=3769275&pid=892606955&vc_url=#{CGI.escape(target)}"
    assert_equal expected, HotpepperAffiliateUrlBuilder.call("https://www.hotpepper.jp/strJ003451218/", template: template)
    generated = HotpepperAffiliateUrlBuilder.call("https://www.hotpepper.jp/strJ003451218/?vos=old&x=1", template: template)
    destination = CGI.parse(URI.parse(generated).query)["vc_url"].first
    assert_equal [["x", "1"], ["vos", "nhppvccp99002"]], URI.decode_www_form(URI.parse(destination).query)
  end

  test "encodes the destination once and preserves the configured publisher link" do
    url = "https://www.hotpepper.jp/strJ001234567/?a=1&b=2"
    template = "https://affiliate.example/redirect?sid=example&url={url_encoded}"
    result = HotpepperAffiliateUrlBuilder.call(url, template: template)
    assert_equal "https://affiliate.example/redirect?sid=example&url=#{CGI.escape(url)}", result
  end

  test "rejects other sites malformed URLs and missing destination placeholders" do
    ["javascript:alert(1)", "https://hotpepper.jp.evil.test/", "https://tabelog.com/"].each do |url|
      assert_raises(ArgumentError) { HotpepperAffiliateUrlBuilder.call(url, template: "https://affiliate.example/?url={url_encoded}") }
    end
    assert_raises(HotpepperAffiliateUrlBuilder::ConfigurationMissing) do
      HotpepperAffiliateUrlBuilder.call("https://www.hotpepper.jp/strJ001234567/", template: nil)
    end
    assert_raises(HotpepperAffiliateUrlBuilder::ConfigurationMissing) do
      HotpepperAffiliateUrlBuilder.call("https://www.hotpepper.jp/strJ001234567/", template: "https://affiliate.example/static")
    end
  end
end
