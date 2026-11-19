require "test_helper"

class PublicArticleTablesTest < ActionView::TestCase
  include ArticlesHelper

  test "public normalization removes presentation and retains structure content and links" do
    source = '<p>前文</p><table style="color:red!important;width:2000px" width="2000" bgcolor="black"><colgroup><col width="900"></colgroup><tr><th colspan="2">見出し</th></tr><tr><td rowspan="2"><span style="color:black" class="old">内容</span></td><td><a href="https://example.com">リンク</a><br>次行</td></tr></table><p>後文</p>'
    original = source.dup
    result = Nokogiri::HTML.fragment(normalize_public_article_tables(source))
    assert_equal original, source
    assert_equal 1, result.css('.published-article-table-scroll > table').size
    assert_empty result.css('table [style], table[style], table[width], table colgroup')
    assert_equal "2", result.at_css('th')['colspan']
    assert_equal "2", result.at_css('td')['rowspan']
    assert_equal 'https://example.com', result.at_css('a')['href']
    assert_includes result.text, '前文'
    assert_includes result.text, '後文'
    assert_equal 1, result.css('br').size
  end
end
