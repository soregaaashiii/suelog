require "test_helper"
class Admin::ReviewsControllerTest < ActionDispatch::IntegrationTest
  test "review moderation requires authentication" do
    get "/panel_8m4k/reviews"
    assert_response :unauthorized
  end
end
