# frozen_string_literal: true

module Api
  module Mobile
    module V1
      # GET /api/mobile/v1/home — the To do list and one card per commitment (H4, E16–E18, E28, E29)
      class HomeController < BaseController
        def show
          # Every row comes through policy_scope (inside MobileHomeSummary); there is no single
          # record to authorise.
          skip_authorization
          render json: MobileHomeSummary.new(user: current_user, scope: method(:policy_scope)).call
        end
      end
    end
  end
end
