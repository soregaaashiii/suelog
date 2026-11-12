require "test_helper"

class ArticleTablesRenderingTest < ActionDispatch::IntegrationTest
  test "published table retains cells while unsafe clipboard HTML is sanitized" do
    content = '<div class="article-table"><table><tbody><tr><th>店名</th><th>説明</th></tr><tr><td>店舗A<a href="https://example.com/" target="_blank" rel="noopener noreferrer">公式サイト</a></td><td>改行<br>続き<img src="x" onerror="alert(1)"><script>alert(2)</script></td></tr></tbody></table></div>'
    attachment = ActionText::Attachment.from_attributes(content_type: "text/html", content: content)
    article = Article.create!(title: "公開表テスト", slug: "public-table-test", body: attachment.to_html, published: true)
    get article_path(article)
    assert_response :success
    assert_select ".article-body .article-table table th", text: "店名"
    assert_select ".article-body .article-table td", text: "店舗A公式サイト"
    assert_select ".article-body .article-table br", count: 1
    assert_select '.article-body .article-table a[href="https://example.com/"]', text: "公式サイト"
    assert_select '.article-body .article-table a[target="_blank"][rel="noopener noreferrer"]', count: 1
    assert_select ".article-body .article-table script", count: 0
    assert_select ".article-body .article-table [onerror]", count: 0
  end
end
