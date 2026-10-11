require "test_helper"
class StoresControllerTest < ActionDispatch::IntegrationTest
  test "obsolete stores route returns 404" do
    get "/stores"
    assert_response :not_found
  end
end
