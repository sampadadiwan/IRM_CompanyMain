# frozen_string_literal: true

module Api
  module Mobile
    module V1
      # GET /api/mobile/v1/home?fund_manager_id= — the To do list and one card per commitment of ONE
      # fund manager (H4, E16–E18, E28; lp-mobile-multi-site MF-H1..MF-E2)
      class HomeController < BaseController
        def show
          # Every row comes through policy_scope (inside MobileHomeSummary); there is no single
          # record to authorise.
          skip_authorization
          render json: MobileHomeSummary.new(user: current_user, scope: method(:policy_scope), fund_manager_id:).call
        end
      end
    end
  end
end
