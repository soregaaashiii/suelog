require "test_helper"
require Rails.root.join("db/migrate/20261102000400_backfill_gurunavi_affiliate_urls")

class GurunaviAffiliateUrlBuilderTest < ActiveSupport::TestCase
  test "matches the supplied LinkShare link exactly" do
    assert_equal "https://click.linksynergy.com/deeplink?id=*wLoiMUEEgU&mid=47268&murl=http%3A%2F%2Fr.gnavi.co.jp%2Fb706112%2F",
      GurunaviAffiliateUrlBuilder.call("http://r.gnavi.co.jp/b706112/")
  end

  test "encodes HTTPS destinations once and retains query parameters" do
    url = "https://r.gnavi.co.jp/abcd123/?a=1&b=x%20y"
    result = GurunaviAffiliateUrlBuilder.call(" #{url} ")
    params = CGI.parse(URI.parse(result).query)
    assert_equal ["*wLoiMUEEgU"], params["id"]
    assert_equal ["47268"], params["mid"]
    assert_equal [url], params["murl"]
  end

  test "rejects unrelated hosts listing pages credentials and malformed URLs" do
    ["https://r.gnavi.co.jp.evil.test/abc/", "https://example.com/abc/", "javascript:alert(1)", "https://r.gnavi.co.jp/", "https://user@r.gnavi.co.jp/abc/", "https://r.gnavi.co.jp:9999/abc/", "https://r.gnavi.co.jp/a b/"].each do |url|
      assert_raises(ArgumentError) { GurunaviAffiliateUrlBuilder.call(url) }
    end
  end

  test "backfill converts only valid pending URLs preserving visibility and existing links" do
    Geocoder.configure(lookup: :test)
    Geocoder::Lookup::Test.set_default_stub([])
    attrs = { address: "大阪市北区梅田1-20", genre: "居酒屋", last_confirmed_on: Date.current }
    pending = Shop.create!(**attrs, name: "変換待ち店舗", gurunavi_url: "http://r.gnavi.co.jp/b706112/", hide_gurunavi_booking_button: true)
    existing = Shop.create!(**attrs, name: "設定済み店舗", gurunavi_url: "https://r.gnavi.co.jp/existing/", gurunavi_affiliate_url: "https://affiliate.example/manual")
    missing = Shop.create!(**attrs, name: "対象なし店舗", gurunavi_url: "https://not-found.local/261102")
    invalid = Shop.create!(**attrs, name: "要確認店舗", gurunavi_url: "https://example.com/abc/")
    2.times { BackfillGurunaviAffiliateUrls.new.up }
    assert_equal GurunaviAffiliateUrlBuilder.call(pending.gurunavi_url), pending.reload.gurunavi_affiliate_url
    assert pending.hide_gurunavi_booking_button?
    assert_equal "https://affiliate.example/manual", existing.reload.gurunavi_affiliate_url
    assert_nil missing.reload.gurunavi_affiliate_url
    assert_nil invalid.reload.gurunavi_affiliate_url
  end
end
