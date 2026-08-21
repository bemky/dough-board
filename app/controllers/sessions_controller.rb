class SessionsController < ApplicationController
  skip_before_action :require_login

  def new
  end

  def create
    if app_password.present? && ActiveSupport::SecurityUtils.secure_compare(params[:password].to_s, app_password.to_s)
      session[:logged_in] = true
      redirect_to params[:redirect_to].presence || root_path
    else
      flash.now[:alert] = "Incorrect password"
      render :new, status: :unauthorized
    end
  end

  def destroy
    reset_session
    redirect_to login_path
  end

  private

  # Falls back to a fixed password in the test environment since
  # config/credentials.yml is gitignored and not expected to exist in CI.
  def app_password
    Rails.application.credentials.password || (Rails.env.test? ? "test-password" : nil)
  end
end
