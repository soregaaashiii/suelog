require "test_helper"
require_relative "../support/search_console_test_helpers"

class SeoPageMetadataEditorTest < ActiveSupport::TestCase
  include SearchConsoleTestHelpers
  setup do
    seed_gsc_catalog
    @path = "/areas/suita"
    @defaults = GeographicPageMetadata.generated(**GeographicPageMetadata.definition(@path), count: 20)
  end

  test "blank initial settings and identical saves do not create changes or history" do
    assert_no_difference ["SeoPageSetting.count", "SeoPageRevision.count"] do
      assert_not edit({ title: "  ", description: "\n" }).changed
    end
    setting = edit({ title: "吹田市の喫煙できる店｜吸えログ" }).setting
    original_time = setting.updated_at
    assert_no_difference "SeoPageRevision.count" do
      assert_not edit({ title: setting.title }, version: setting.version_token).changed
    end
    assert_equal original_time, setting.reload.updated_at
  end

  test "saves normalized text and immutable before and after effective snapshots" do
    setting = edit({ title: "  個別のタイトル\n｜吸えログ  ", description: "  個別の説明文  " }, note: "CTR改善").setting
    assert_equal "個別のタイトル ｜吸えログ", setting.title
    assert_equal "個別の説明文", setting.description
    first = setting.revisions.sole
    assert_equal @defaults[:title], first.before_values["effective_title"]
    assert_nil first.before_values["title"]
    assert_equal setting.title, first.after_values["effective_title"]
    assert_equal "CTR改善", first.change_note
    edit({ title: "次のタイトル" }, version: setting.version_token)
    assert_equal 2, setting.revisions.count
    assert_equal "個別の説明文", setting.reload.description
    assert_equal "個別のタイトル ｜吸えログ", first.reload.after_values["effective_title"]
  end

  test "clearing each field restores dynamic generation and records reset values" do
    setting = edit({ title: "個別タイトル", description: "個別説明" }).setting
    new_defaults = GeographicPageMetadata.generated(**GeographicPageMetadata.definition(@path), count: 21)
    result = SeoPageMetadataEditor.new(path: @path, attributes: { title: nil, description: nil }, expected_version: setting.version_token, defaults: new_defaults).call
    assert result.changed
    assert_not result.setting.customized?
    last = result.setting.revisions.order(:id).last
    assert_nil last.after_values["title"]
    assert_nil last.after_values["description"]
    assert_equal new_defaults[:description], last.after_values["effective_description"]
    assert_equal "個別説明", last.before_values["effective_description"]
    assert_equal @defaults[:description], setting.revisions.order(:id).first.before_values["effective_description"]
  end

  test "rejects stale and formerly new forms without overwriting another edit" do
    setting = edit({ title: "最初の保存" }).setting
    assert_raises(SeoPageMetadataEditor::Conflict) { edit({ title: "古い新規画面" }, version: "new") }
    version = setting.version_token
    edit({ title: "別画面から更新" }, version: version)
    assert_no_difference "SeoPageRevision.count" do
      assert_raises(SeoPageMetadataEditor::Conflict) { edit({ title: "古い内容で上書き" }, version: version) }
    end
    assert_equal "別画面から更新", setting.reload.title
  end

  test "invalid values and unknown URLs never persist partially" do
    [{ title: "x" * 201 }, { description: "x" * 501 }].each do |attributes|
      assert_no_difference ["SeoPageSetting.count", "SeoPageRevision.count"] do
        assert_raises(ActiveRecord::RecordInvalid) { edit(attributes) }
      end
    end
    assert_raises(ActiveRecord::RecordInvalid) { edit({ title: "有効なタイトル" }, note: "x" * 501) }
    assert_raises(ActiveRecord::RecordInvalid) do
      SeoPageMetadataEditor.new(path: "/shops/1", attributes: { title: "対象外" }, expected_version: "new", defaults: @defaults).call
    end
    assert_nil GeographicPageMetadata.definition("/areas/suita?open_now_only=1")
    assert_nil GeographicPageMetadata.definition("https://example.com/areas/suita")
  end

  private

  def edit(attributes, version: "new", note: nil)
    SeoPageMetadataEditor.new(path: @path, attributes: attributes, expected_version: version, defaults: @defaults, change_note: note).call
  end
end
