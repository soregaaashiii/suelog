require "test_helper"
require_relative "../support/search_console_test_helpers"

class ArticlePageLinksTest < ActiveSupport::TestCase
  include SearchConsoleTestHelpers
  setup do
    seed_gsc_catalog
    Article.update_all(published: false)
    @shop = Shop.find_by!(name: "実績テスト0")
  end

  test "matches stored shortcodes and exact local links but not titles external links or substrings" do
    card = article("card", "[shop id=#{@shop.id}]")
    absolute = article("absolute", %(<a href="https://suelog.jp/shops/#{@shop.id}?from=test">店舗</a>))
    article("external", %(<a href="https://example.com/shops/#{@shop.id}">店舗</a>))
    article("substring", %(<a href="/shops/#{@shop.id}0">別店舗</a>))
    article("title-only", "関連のない本文", title: "吹田市の居酒屋")
    assert_equal [absolute.id, card.id].sort, ArticlePageLinks.new.for_shop(@shop).map(&:id).sort
    directory = GeographicDirectory.new
    assert_equal [absolute.id, card.id].sort, ArticlePageLinks.new(directory).for_page(directory.definition("region", "suita")).map(&:id).sort
  end

  test "matches embedded table links and explicit geography links without fabricating article backlinks" do
    content = %(<table><tr><td><a href="/shops/#{@shop.id}">店</a></td></tr></table>)
    attachment = ActionText::Attachment.from_attributes(content_type: "text/html", content: content)
    table = article("embedded", attachment.to_html)
    page = article("page", '<a href="/areas/suita/genre/izakaya">一覧</a>')
    directory = GeographicDirectory.new
    facets = GeographicFacets.new(directory)
    assert_includes ArticlePageLinks.new.for_shop(@shop).map(&:id), table.id
    assert_includes ArticlePageLinks.new(directory).for_page(directory.definition("region", "suita"), facet: facets.definition("genre", "izakaya")).map(&:id), page.id
    assert_includes ArticlePageLinks.new(directory).for_page(directory.definition("region", "suita")).map(&:id), page.id
    assert_empty ArticlePageLinks.new.for_article(page)
    assert_equal %w[/areas/suita /stations/esaka], ArticlePageLinks.new.for_article(table).map { |link| link[:path] }
    table.update!(body: "[shop id=#{@shop.id}] <a href='/areas/suita'>地域</a>")
    assert_equal ["/stations/esaka"], ArticlePageLinks.new.for_article(table).map { |link| link[:path] }
  end

  test "excludes drafts scheduled articles and revoked shops even after warming the reference cache" do
    visible = article("visible", "[shop id=#{@shop.id}]")
    article("draft", "[shop id=#{@shop.id}]", published: false)
    article("future", "[shop id=#{@shop.id}]", published_at: 1.day.from_now)
    assert_equal [visible.id], ArticlePageLinks.new.for_shop(@shop).map(&:id)
    visible.update_columns(published: false)
    assert_empty ArticlePageLinks.new.for_shop(@shop)
    visible.update!(published: true)
    ArticlePageLinks.new.for_shop(@shop)
    @shop.update_columns(approved: false)
    directory = GeographicDirectory.new
    assert_empty ArticlePageLinks.new(directory).for_page(directory.definition("region", "suita"))
    assert_empty ArticlePageLinks.new.for_article(visible)
  end

  test "body edits invalidate the reference index and selection is capped" do
    first = article("first", "[shop id=#{@shop.id}]")
    assert_equal [first.id], ArticlePageLinks.new.for_shop(@shop).map(&:id)
    first.update!(body: "店舗紹介を削除")
    assert_empty ArticlePageLinks.new.for_shop(@shop)
    5.times { |i| article("extra-#{i}", "[shop id=#{@shop.id}]") }
    assert_equal 3, ArticlePageLinks.new.for_shop(@shop).size
  end

  test "loads article references in batches rather than querying once per article" do
    12.times { |i| article("batch-#{i}", "[shop id=#{@shop.id}]") }
    directory = GeographicDirectory.new
    entry = directory.definition("region", "suita")
    directory.statistics
    ArticlePageLinks.new(directory).for_page(entry)
    queries = []
    callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] if payload[:sql].match?(/\ASELECT/i) && !payload[:cached] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      assert_equal 3, ArticlePageLinks.new(directory).for_page(entry).size
    end
    assert_operator queries.size, :<=, 6
  end

  private

  def article(slug, body, **attrs)
    Article.create!({ title: slug, slug: slug, body: body, published: true, published_at: 1.day.ago }.merge(attrs))
  end
end
