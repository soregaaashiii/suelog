require "test_helper"

class ArticleTest < ActiveSupport::TestCase
  test "sends aicoo activity when article is created" do
    with_aicoo_activity_stub do |calls|
      article = Article.create!(title: "梅田喫煙カフェまとめ", slug: "umeda-smoking-cafe-test", summary: "summary")

      payload = calls.last
      assert_equal "suelog", payload[:business_key]
      assert_equal "article_created", payload[:activity_type]
      assert_equal "article", payload[:source_type]
      assert_equal article.id, payload[:source_id]
      assert_equal "Article", payload[:resource_type]
      assert payload[:callback_registered]
      assert payload[:callback_called]
      assert_includes payload[:title], "記事を追加"
      assert_equal article.slug, payload[:metadata][:slug]
    end
  end

  test "sends seo activity when article seo fields are updated" do
    article = Article.create!(title: "難波喫煙居酒屋", slug: "namba-smoking-izakaya-test", summary: "summary")

    with_aicoo_activity_stub do |calls|
      article.update!(seo_title: "難波 喫煙 居酒屋まとめ")

      payload = calls.last
      assert_equal "article_seo_updated", payload[:activity_type]
      assert_equal "article", payload[:source_type]
      assert_includes payload[:metadata][:changed_fields], "seo_title"
    end
  end

  test "sends activity when ActionText body is updated" do
    article = Article.create!(title: "梅田喫煙バー", slug: "umeda-smoking-bar-test", summary: "summary")

    with_aicoo_activity_stub do |calls|
      article.update!(body: '<p><a href="/articles/related">関連記事</a></p>')

      payload = calls.last
      assert_equal "article_updated", payload[:activity_type]
      assert_includes payload[:metadata][:changed_fields], "body"
    end
  end

  private

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
