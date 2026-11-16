require "application_system_test_case"

class AdminShopImportFlowTest < ApplicationSystemTestCase
  test "repeated Enter submits provisional and final registration only once" do
    visit admin_url(new_admin_shop_import_path)
    visit new_admin_shop_import_path
    fill_in "raw_text", with: tabelog_text
    click_on "解析する"

    assert_text "解析結果"

    3.times do
      assert_no_difference("Shop.where(name: 'Enter連打テスト店舗').count") do
        dismiss_confirm("重複候補がある場合でも新規登録します。よろしいですか？") do
          dispatch_repeated_enter("h2", count: 1)
        end
      end
      assert_selector 'input[value="この内容で新規仮登録する"]:not([disabled])'
    end

    assert_difference("Shop.where(name: 'Enter連打テスト店舗').count", 1) do
      accept_confirm("重複候補がある場合でも新規登録します。よろしいですか？") do
        dispatch_repeated_enter("h2")
      end
      assert_text "店舗編集（管理者用）"
    end

    shop = Shop.find_by!(name: "Enter連打テスト店舗")
    assert_not shop.approved?

    2.times do
      dismiss_confirm("更新して承認しますか？") do
        dispatch_repeated_enter("#shop_name")
      end
      assert_not shop.reload.approved?
      assert_selector 'input[type="submit"][name="commit_action"][value="approve"]:not([disabled])'
    end

    accept_confirm("更新して承認しますか？") do
      dispatch_repeated_enter("#shop_name")
    end

    assert_text "食べログ貼り付けインポート"
    assert shop.reload.approved?
    assert_equal 1, Shop.where(name: shop.name).count
  end

  private

  def admin_url(path)
    server = Capybara.current_session.server
    "http://kawa_admin_92:X9f%21pL3%23sK@#{server.host}:#{server.port}#{path}"
  end

  def dispatch_repeated_enter(selector, count: 3)
    page.execute_script(<<~JS)
      const target = document.querySelector(#{selector.to_json});
      for (let index = 0; index < #{count}; index += 1) {
        target.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
      }
    JS
  end

  def tabelog_text
    <<~TEXT
      店名
      Enter連打テスト店舗
      ジャンル
      居酒屋
      住所
      大阪府大阪市北区梅田7-7-7
      交通手段
      大阪駅から100m
      禁煙・喫煙
      全席喫煙可
    TEXT
  end
end
