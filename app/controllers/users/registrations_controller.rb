module Users
  class RegistrationsController < Devise::RegistrationsController
    prepend_before_action :require_no_authentication, only: %i[new cancel]
    # Dont allow users to sign up on their own
    before_action :authenticate_user!

    # POST /resource
    def create
      build_resource(sign_up_params)

      ensure_entity(resource)
      resource.save

      yield resource if block_given?
      if resource.persisted?
        if resource.active_for_authentication?
          set_flash_message! :notice, :signed_up
          sign_up(resource_name, resource)
          respond_with resource, location: after_sign_up_path_for(resource)
        else
          set_flash_message! :notice, :"signed_up_but_#{resource.inactive_message}"
          expire_data_after_sign_in!
          respond_with resource, location: after_inactive_sign_up_path_for(resource)
        end
      else
        clean_up_passwords resource
        set_minimum_password_length
        # respond_with resource
        redirect_to new_user_path(params.to_unsafe_h), alert: resource.errors.full_messages.join(", ")
      end
    end

    protected

    def after_sign_up_path_for(resource)
      if current_user
        dashboard_entities_path
      elsif is_navigational_format?
        after_sign_in_path_for(resource)
      end
    end

    def after_inactive_sign_up_path_for(_resource)
      welcome_users_path
    end

    def ensure_entity(resource)
      # Ensure that users are created only for the same entity as the logged in user.
      if current_user && !current_user.has_role?(:super)
        resource.entity_id = current_user.entity_id
        logger.debug "Setting new user entity to logged in users entity #{current_user.entity_id}"
      end
    end
  end
end
