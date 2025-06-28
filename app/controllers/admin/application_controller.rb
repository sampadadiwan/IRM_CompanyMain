# All Administrate controllers inherit from this
# `Administrate::ApplicationController`, making it the ideal place to put
# authentication logic or other before_actions.
#
# If you want to add pagination or other controller-level concerns,
# you're free to overwrite the RESTful controller actions.
module Admin
  class ApplicationController < Administrate::ApplicationController
    include Administrate::Punditize

    helper all_helpers_from_path "app/packs/core/base/helpers"

    before_action :authenticate_admin

    def authenticate_admin
      redirect_to '/', alert: 'Not authorized.' unless current_user&.has_role?(:super) || current_user&.has_role?(:support)
    end

    rescue_from Pundit::NotAuthorizedError do |_exception|
      redirect_to root_path, alert: "Access Denied"
    end
  end
end
