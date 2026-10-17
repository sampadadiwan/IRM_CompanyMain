# frozen_string_literal: true

module Api
  module Mobile
    module V1
      # PUT /api/mobile/v1/device { push_token, push_enabled, app_version } — this phone's push
      # address and its per-phone push switch (H10, E7, E26).
      class DevicesController < BaseController
        def update
          authorize current_device, :update?
          current_device.update_push!(token: params[:push_token].presence, enabled: params[:push_enabled],
                                      app_version: params[:app_version].presence)
          render json: { id: current_device.id, push_enabled: current_device.push_enabled,
                         push_status: current_device.push_status }
        end
      end
    end
  end
end
