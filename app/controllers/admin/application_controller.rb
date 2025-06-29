# All Administrate controllers inherit from this
# `Administrate::ApplicationController`, making it the ideal place to put
# authentication logic or other before_actions.
#
# If you want to add pagination or other controller-level concerns,
# you're free to overwrite the RESTful controller actions.
module Admin
  class ApplicationController < Administrate::ApplicationController
    include Administrate::Punditize
    include Pagy::Backend

    helper all_helpers_from_path "app/packs/core/base/helpers"

    before_action :authenticate_admin

    def dashboard_class
      "#{resource_class.name}Dashboard".constantize
    end

    def authenticate_admin
      redirect_to '/', alert: 'Not authorized.' unless current_user&.has_role?(:super) || current_user&.has_role?(:support)
    end

    rescue_from Pundit::NotAuthorizedError do |_exception|
      redirect_to root_path, alert: "Access Denied"
    end

    # Pagy-backed index for all Admin controllers
    def index
      search_term = params[:search]
      resources = Administrate::Search.new(scoped_resource, dashboard_class.new, search_term).run

      resources = apply_resource_filters(resources) if respond_to?(:apply_resource_filters)
      resources = order.apply(resources)

      @pagy, @resources = pagy(resources, page: params[:_page], items: 20)

      # This builds the expected `page` object for the view
      page = Administrate::Page::Collection.new(dashboard, order: order)

      render :index, locals: {
        resources: @resources,
        search_term: search_term,
        page: page,
        pagy: @pagy,
        show_search_bar: true # or false if you don't want the search bar
      }
    end
  end
end
