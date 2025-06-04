require "test_helper"

class SkincareAnalysesControllerTest < ActionDispatch::IntegrationTest
  test "should get new" do
    get skincare_analyses_new_url
    assert_response :success
  end

  test "should get create" do
    get skincare_analyses_create_url
    assert_response :success
  end
end
