require "test_helper"

class RestaurantUrlSearchJobTest < ActiveJob::TestCase
  setup do
    Geocoder.configure(lookup: :test)
    Geocoder::Lookup::Test.set_default_stub([])
    @shop = Shop.create!(name: "段階検索確認店", address: "大阪市北区梅田1-2-3", phone: "06-1234-5678", genre: "居酒屋", last_confirmed_on: Date.current, approved: true, smoking_area: :all_smoking, smoking_type: :both_ok)
    @run = RestaurantUrlSearchRun.create!(shop: @shop, provider: "gurunavi", state: "pending", run_token: "test-token", input_digest: RestaurantUrlSearchRun.input_digest(@shop, "gurunavi"))
    @matched = { state: "matched", url: "https://r.gnavi.co.jp/abcd123/", reason: "照合一致", queries: [], candidates: [] }
  end

  def perform_result(result)
    search = Object.new
    search.define_singleton_method(:call) { result }
    with_search(search) { RestaurantUrlSearchJob.perform_now(@run.id, "test-token") }
  end

  def with_search(search)
    original = RestaurantUrlSearch::Search.method(:new)
    RestaurantUrlSearch::Search.define_singleton_method(:new) { |*| raise "Unexpected search" unless search; search }
    yield
  ensure
    RestaurantUrlSearch::Search.define_singleton_method(:new, original)
  end

  test "verified normal URL is passed to existing affiliate conversion and stores evidence" do
    perform_result(@matched)
    assert_equal "https://r.gnavi.co.jp/abcd123/", @shop.reload.gurunavi_url
    assert_equal GurunaviAffiliateUrlBuilder.call(@shop.gurunavi_url), @shop.gurunavi_affiliate_url
    assert_equal "matched", @run.reload.state
    assert_equal "照合一致", @run.payload["reason"]
  end

  test "hotpepper verified URL still uses existing campaign conversion" do
    @run.update!(provider: "hotpepper", input_digest: RestaurantUrlSearchRun.input_digest(@shop, "hotpepper"))
    url = "https://www.hotpepper.jp/strJ001234567/"
    perform_result(@matched.merge(url: url))
    assert_equal url, @shop.reload.hotpepper_url
    assert_equal HotpepperAffiliateUrlBuilder.call(url), @shop.hotpepper_affiliate_url
    assert_equal "matched", @run.reload.state
  end

  test "uncertain candidates and unavailable API leave source and affiliate unset" do
    perform_result(@matched.merge(state: "review", url: nil))
    assert_nil @shop.reload.gurunavi_url
    assert_nil @shop.gurunavi_affiliate_url
    assert_equal "review", @run.reload.state
  end

  test "concurrent manual change or moved shop prevents stale result from being saved" do
    @shop.update!(gurunavi_url: "https://r.gnavi.co.jp/manual123/", gurunavi_affiliate_url: "https://affiliate.example/manual")
    perform_result(@matched)
    assert_equal "https://r.gnavi.co.jp/manual123/", @shop.reload.gurunavi_url
    assert_equal "https://affiliate.example/manual", @shop.gurunavi_affiliate_url
    assert_equal "review", @run.reload.state
    assert_includes @run.payload["reason"], "変更"
  end

  test "stale run tokens do not perform a search or mutate data" do
    @run.update!(run_token: "new-token")
    with_search(nil) do
      RestaurantUrlSearchJob.perform_now(@run.id, "test-token")
    end
    assert_nil @shop.reload.gurunavi_url
  end
end
