class ApplicationController < ActionController::Base
  include StandardAPI::Controller
  include StandardAPI::AccessControlList

  before_action :require_login
  # Demo mode is a property of the request being rendered, so it's carried on
  # Current rather than threaded through every view that shows a holding.
  before_action :set_demo_mode

  helper_method :demo_mode?

  # Monkey Patch StandardAPI#create to redirect
  def create
    record = model.new(model_params)
    instance_variable_set("@#{model.model_name.singular}", record)

    if record.save
      if request.format == :html
        if params["redirect_to"]
          redirect_to params["redirect_to"] 
        else
          redirect_to url_for(
            controller: record.class.base_class.model_name.collection,
            action: 'show',
            id: record.id,
            only_path: true
          )
        end
        
      else
        render :show, status: :created
      end
    else
      if request.format == :html
        render :new, status: :bad_request
      else
        render :show, status: :bad_request
      end
    end
  end

  private

  def require_login
    unless session[:logged_in]
      redirect_to login_path(redirect_to: request.fullpath)
    end
  end

  def set_demo_mode
    Current.demo = session[:demo]
  end

  def demo_mode?
    DemoMode.enabled?
  end
end
