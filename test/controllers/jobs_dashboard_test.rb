require "test_helper"

# Sidekiq's dashboard mounts as a Rack app, so it bypasses ApplicationController
# and its before_action :require_login. These cover the constraint standing in
# for that — see LoggedInConstraint.
class JobsDashboardTest < ActionDispatch::IntegrationTest

  test "a logged-out request is sent to the login form" do
    get "/jobs"
    assert_redirected_to login_path(redirect_to: "/jobs")
  end

  test "a logged-out request to a page inside the dashboard is sent there too" do
    get "/jobs/retries"
    assert_redirected_to login_path(redirect_to: "/jobs/retries")
  end

  test "the dashboard closes again on logout" do
    sign_in
    delete logout_path

    get "/jobs"
    assert_redirected_to login_path(redirect_to: "/jobs")
  end

  test "a logged-in request is handed to the dashboard, not the login form" do
    sign_in

    redirected_to_login = begin
      get "/jobs"
      response.redirect? && response.location.to_s.include?(login_path)
    rescue RedisClient::CannotConnectError
      # Getting as far as Redis is the proof: the constraint matched and the
      # router handed off to Sidekiq::Web. Rendering the dashboard itself needs
      # a Redis the test environment doesn't run.
      false
    end

    assert_not redirected_to_login
  end

  test "the redirect is a 302, so a browser will not cache it past login" do
    get "/jobs"
    assert_response :found
  end

end
