# Sidekiq's dashboard mounts as a Rack app, so requests to it never pass through
# ApplicationController and never run its `before_action :require_login`. This
# is that same check, expressed as something the router can ask before handing
# a request to a mounted app.
#
# It reads the session Rails' middleware has already populated, so the dashboard
# is behind exactly the password the rest of the app is — no second credential
# to keep, and logging out closes it too.
class LoggedInConstraint

  def self.matches?(request)
    request.session[:logged_in].present?
  end

end
