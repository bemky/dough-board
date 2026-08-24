# Turns demo mode on and off for this browser. It's a session flag rather than
# a setting because it describes an occasion — showing somebody the app — and
# not the installation; a deploy that only ever exists to be shown sets
# DEMO_MODE instead, and then there is nothing here to switch off.
class DemoController < ApplicationController

  def update
    if DemoMode.forced?
      redirect_back fallback_location: root_path,
        alert: "Demo mode is on for this whole deployment (DEMO_MODE)."
      return
    end

    session[:demo] = !session[:demo]
    redirect_back fallback_location: root_path,
      notice: session[:demo] ? "Demo mode on — holdings are shown at a fraction of what's held." : "Demo mode off."
  end

end
