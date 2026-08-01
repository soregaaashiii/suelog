require "test_helper"

class Admin::NavigationHelperTest < ActionView::TestCase
  include Admin::NavigationHelper

  test "pending navigation counts keep their values with one database query" do
    expected = {
      reviews: Review.where(status: 0).count,
      shops: Shop.where(approved: false).where(rejected: [false, nil]).count,
      edit_requests: ShopEditRequest.where(status: 0).count,
      reports: ShopReport.where(status: 0).count + ReviewReport.where(status: 0).count
    }
    sql = []
    subscriber = lambda do |_name, _started, _finished, _id, payload|
      sql << payload[:sql].to_s unless payload[:name] == "SCHEMA" || payload[:cached]
    end

    values = ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      {
        reviews: pending_reviews_count,
        shops: pending_shops_count,
        edit_requests: pending_edit_requests_count,
        reports: pending_reports_count
      }
    end

    assert_equal expected, values
    assert_equal 1, sql.count { |statement| statement.include?("COUNT(*)") }
  end
end
