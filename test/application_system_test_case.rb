require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :chrome, screen_size: [1400, 1400]

  def sign_in
    visit login_path
    fill_in "password", with: "test-password"
    click_button "Log in"
  end
end
