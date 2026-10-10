require 'test_helper'
class ReviewsControllerTest < ActionDispatch::IntegrationTest
  test 'standalone review registration is not a public route' do
    get '/reviews/new'
    assert_response :not_found
  end
  test 'review creation rejects an unknown shop' do
    post '/shops/999999999/reviews', params: { review: { rating: 4 } }
    assert_response :not_found
  end
end
