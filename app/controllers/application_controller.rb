class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception

  check_authorization unless: :devise_controller?
  rescue_from CanCan::AccessDenied do |exception|
   if current_user
     redirect_to root_url, alert: "Sorry, you don't have permission to do that."
   else
     redirect_to new_user_session_url
   end
  end

  protected

    def after_sign_in_path_for(resource)
      return edit_user_path(resource) unless resource.sign_in_count > 2 || resource.has_full_profile?
      super
    end

end