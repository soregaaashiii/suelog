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
      htmlClipboard.setData("text/html", '<table><tr><td>HTML貼付<br>改行</td><td>&lt;b&gt;文字&lt;/b&gt;</td></tr></table>');
      document.querySelector('[aria-label="1行1列"]').dispatchEvent(new ClipboardEvent("paste", { clipboardData: htmlClipboard, bubbles: true, cancelable: true }));
    JS
    assert_field "1行1列", with: "HTML貼付\n改行"
    assert_field "1行2列", with: "<b>文字</b>"
    fill_in "1行1列", with: "店名"
    fill_in "1行2列", with: "料金"
    assert_field "3行2列", with: "2行\nの説明"
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
    assert_field "3行2列", with: "2行\nの説明"
    fill_in "2行1列", with: "店舗A修正"
    click_on "表を反映する"
    click_on "保存", exact: true
    assert_current_path admin_articles_path
    assert_includes article.reload.body.to_s, "店舗A修正"
    assert_includes article.body.to_s, "既存の文章"
    assert_equal 1, Nokogiri::HTML.fragment(article.body.to_s).css("table").length
  end
end
