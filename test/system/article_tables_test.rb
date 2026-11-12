require "application_system_test_case"

class ArticleTablesTest < ApplicationSystemTestCase
  setup { Capybara.enable_aria_label = true }
  teardown { Capybara.enable_aria_label = false }
  test "create paste edit save and reopen a table without losing cells" do
    article = Article.create!(title: "表の保存テスト", slug: "table-system-test", body: "既存の文章")
    credentials = Rails.root.join("app/controllers/admin/base_controller.rb").read.match(/name: "([^"]+)", password: "([^"]+)"/)
    server = Capybara.current_session.server
    visit "http://#{ERB::Util.url_encode(credentials[1])}:#{ERB::Util.url_encode(credentials[2])}@#{server.host}:#{server.port}#{edit_admin_article_path(article)}"
    visit edit_admin_article_path(article)
    page.execute_script(<<~'JS')
      const bodyClipboard = new DataTransfer();
      bodyClipboard.setData("text/plain", "見出しA\t見出しB\n本文A\t本文B");
      document.querySelector('trix-editor').dispatchEvent(new ClipboardEvent("paste", { clipboardData: bodyClipboard, bubbles: true, cancelable: true }));
    JS
    assert_selector "dialog[open]"
    assert_field "1行1列", with: "見出しA"
    click_on "キャンセル"
    assert_no_selector "trix-editor table"
    click_on "表を作成・編集"
    assert_selector "dialog[open]"
    fill_in "1行1列", with: "店名"
    fill_in "1行2列", with: "料金"
    page.execute_script(<<~'JS')
      const clipboard = new DataTransfer();
      clipboard.setData("text/plain", '店舗A\t1000円\n店舗B\t"2行\nの説明"\n');
      document.querySelector('[aria-label="2行1列"]').dispatchEvent(new ClipboardEvent("paste", { clipboardData: clipboard, bubbles: true, cancelable: true }));
    JS
    page.execute_script(<<~'JS')
      const htmlClipboard = new DataTransfer();
      htmlClipboard.setData("text/html", '<table><tr><td>HTML貼付<br>改行</td><td>&lt;b&gt;文字&lt;/b&gt;</td><td><a href="https://example.net/">コピー元リンク</a></td></tr></table>');
      document.querySelector('[aria-label="1行1列"]').dispatchEvent(new ClipboardEvent("paste", { clipboardData: htmlClipboard, bubbles: true, cancelable: true }));
    JS
    assert_field "1行1列", with: "HTML貼付\n改行"
    assert_field "1行2列", with: "<b>文字</b>"
    assert_field "1行3列", with: "[コピー元リンク](https://example.net/)"
    fill_in "1行1列", with: "店名"
    fill_in "1行2列", with: "料金"
    assert_field "3行2列", with: "2行\nの説明"
    fill_in "2行3列", with: ""
    find('[aria-label="2行3列"]').click
    find('[data-article-table-target="linkText"]').set("公式サイト")
    find('[data-article-table-target="linkUrl"]').set("https://example.com/?a=1&b=2")
    click_on "選んだセルにリンクを追加"
    assert_field "2行3列", with: "[公式サイト](https://example.com/?a=1&b=2)"
    fill_in "3行3列", with: "https://example.org/"
    click_on "表を反映する"
    assert_selector "trix-editor .article-table th", text: "店名"
    assert_selector "trix-editor .article-table td", text: "店舗B"
    fill_in "article_title", with: "表の保存テスト"

    click_on "保存", exact: true
    assert_current_path admin_articles_path
    visit edit_admin_article_path(article)
    assert_selector "trix-editor .article-table td", text: "店舗A"
    page.execute_script(<<~'JS')
      const editor = document.querySelector('trix-editor').editor;
      const attachment = editor.getDocument().getAttachments()[0];
      editor.setSelectedRange(editor.getDocument().getRangeOfAttachment(attachment));
    JS
    click_on "表を作成・編集"
    assert_field "2行1列", with: "店舗A"
    assert_field "2行3列", with: "[公式サイト](https://example.com/?a=1&b=2)"
    assert_field "3行3列", with: "[https://example.org/](https://example.org/)"
    assert_field "3行2列", with: "2行\nの説明"
    fill_in "2行1列", with: "店舗A修正"
    click_on "表を反映する"
    click_on "保存", exact: true
    assert_current_path admin_articles_path
    assert_includes article.reload.body.to_s, "店舗A修正"
    assert_includes article.body.to_s, "既存の文章"
    fragment = Nokogiri::HTML.fragment(article.body.to_s)
    assert_equal "https://example.com/?a=1&b=2", fragment.css(".article-table a").find { |link| link.text == "公式サイト" }["href"]
    assert_equal 1, Nokogiri::HTML.fragment(article.body.to_s).css("table").length
  end
  test "paste prose and multiple nested tables in order and retain them after saving" do
    article = Article.create!(title: "文章と表", slug: "mixed-table-test", body: "元の文章")
    credentials = Rails.root.join("app/controllers/admin/base_controller.rb").read.match(/name: "([^"]+)", password: "([^"]+)"/)
    server = Capybara.current_session.server
    visit "http://#{ERB::Util.url_encode(credentials[1])}:#{ERB::Util.url_encode(credentials[2])}@#{server.host}:#{server.port}#{edit_admin_article_path(article)}"
    visit edit_admin_article_path(article)
    page.execute_script(<<~'JS')
      const clipboard = new DataTransfer();
      clipboard.setData("text/html", '<div><h2>貼付見出し</h2><p>前の文章 <a href="https://example.com/">外部リンク</a></p><div><table><tr><th>表一見出し</th></tr><tr><td>表一内容</td></tr></table><p>間の文章</p><table><tr><td>表二内容</td></tr></table></div><p>後の文章</p></div>');
      const editor = document.querySelector('trix-editor');
      editor.editor.setSelectedRange([0, 0]);
      editor.dispatchEvent(new ClipboardEvent("paste", { clipboardData: clipboard, bubbles: true, cancelable: true }));
    JS
    assert_no_selector "dialog[open]"
    assert_selector "trix-editor table", count: 2
    assert_selector "trix-editor", text: "貼付見出し"
    assert_selector 'trix-editor a[href="https://example.com/"]', text: "外部リンク"
    click_on "保存", exact: true
    assert_current_path admin_articles_path
    visit edit_admin_article_path(article)
    assert_selector "trix-editor table", count: 2
    content = Nokogiri::HTML.fragment(article.reload.body.to_s)
    positions = ["前の文章", "表一内容", "間の文章", "表二内容", "後の文章", "元の文章"].map { |text| content.text.index(text) }
    assert positions.all?
    assert_equal positions.sort, positions
    assert_equal "表一見出し", content.at_css("table th").text
  end

end
