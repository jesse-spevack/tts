require "test_helper"

class DocsControllerTest < ActionDispatch::IntegrationTest
  test "GET /docs/mpp renders the MPP API reference" do
    get docs_mpp_path

    assert_response :ok
    assert_select "h1", text: /article into a podcast/i
    assert_select "a[href='http://mpp.dev/']"
    assert_select "section#voices"
    assert_select "section#rate-limits"
  end

  test "GET /docs/mpp does not require authentication" do
    get docs_mpp_path

    assert_response :ok
  end
end
