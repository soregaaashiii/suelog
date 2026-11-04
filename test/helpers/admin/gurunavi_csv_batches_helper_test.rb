require "test_helper"
class Admin::GurunaviCsvBatchesHelperTest < ActionView::TestCase
  include Admin::GurunaviCsvBatchesHelper
  test "differences use explicit red styling rather than a match marker" do
    output = csv_difference("カフェABC梅田店", "カフェXYZ梅田店")
    assert_includes output, 'class="csv-difference"'
    assert_includes output, '>ABC</span>'
    assert_includes output, "相手側の表記と異なる部分"
    assert_not_includes output, "<mark"
    assert_equal "カフェABC", csv_difference("カフェABC", "カフェABC")
  end
  test "unrelated values are marked as differences and escaped" do
    output = csv_difference("<script>alert(1)</script>", "別店舗")
    assert_includes output, "&lt;script&gt;"
    assert_not_includes output, "<script>"
    assert_equal "（空欄）", csv_difference(nil, "店舗")
  end
end
