require "test_helper"

class LoggedInConstraintTest < ActiveSupport::TestCase

  def request_with(session)
    ActionDispatch::Request.new("rack.session" => session)
  end

  test "matches a logged-in session" do
    assert LoggedInConstraint.matches?(request_with({logged_in: true}))
  end

  test "does not match a session that never logged in" do
    assert_not LoggedInConstraint.matches?(request_with({}))
  end

  test "does not match a session whose flag was cleared" do
    assert_not LoggedInConstraint.matches?(request_with({logged_in: nil}))
    assert_not LoggedInConstraint.matches?(request_with({logged_in: false}))
  end

end
