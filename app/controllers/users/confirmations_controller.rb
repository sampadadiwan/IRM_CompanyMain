# frozen_string_literal: true

module Users
  class ConfirmationsController < Devise::ConfirmationsController
    def after_confirmation_path_for(resource_name, resource)
      sign_in(resource)
      super
    end

    def force_password_reset
      token = current_user.send(:set_reset_password_token)
      edit_user_password_path(:user, reset_password_token: token)
    end

    # GET /resource/confirmation/new
    # def new
    #   super
    # end

    # POST /resource/confirmation
    # def create
    #   super
    # end

    # GET /resource/confirmation?confirmation_token=abcdef
    def show
      ActiveRecord::Base.connected_to(role: :writing) do
        super
      end
    end

    # protected

    # The path used after resending confirmation instructions.
    # def after_resending_confirmation_instructions_path_for(resource_name)
    #   super(resource_name)
    # end

    # The path used after confirmation.
    # def after_confirmation_path_for(resource_name, resource)
    #   super(resource_name, resource)
    # end
  end
end
