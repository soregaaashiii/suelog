require 'test_helper'
class ShopsControllerTest < ActionDispatch::IntegrationTest
  test 'legacy shops index redirects permanently to public search' do
    get '/shops'
    assert_response :moved_permanently
    assert_redirected_to '/'
  end
end
