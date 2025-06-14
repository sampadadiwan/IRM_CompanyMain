# config/initializers/doorkeeper_force_primary.rb
module Doorkeeper
  module AuthorizationsControllerPatch
    extend ActiveSupport::Concern

    included do
      around_action :use_primary_for_authorize
    end

    def use_primary_for_authorize(&)
      ActiveRecord::Base.connected_to(role: :writing, &)
    end
  end
end

Rails.application.config.to_prepare do
  Doorkeeper::AuthorizationsController.include Doorkeeper::AuthorizationsControllerPatch
end
