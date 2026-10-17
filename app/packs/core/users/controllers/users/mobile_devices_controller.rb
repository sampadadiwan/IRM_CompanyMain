module Users
  # Website › Profile › Devices: the phones a user has signed in to the LP mobile app, with
  # Sign out for a lost phone (lp-mobile-app design card ③; worked example H14).
  class MobileDevicesController < ApplicationController
    def index
      authorize MobileDevice
      # A user has at most a handful of rows (10 live + whatever they signed out)
      @mobile_devices = policy_scope(MobileDevice).order(Arel.sql("revoked_at IS NULL DESC"), last_used_at: :desc)
    end

    # H14 — ends that phone's session at once and stops its pushes
    def destroy
      @mobile_device = policy_scope(MobileDevice).find(params[:id])
      authorize @mobile_device
      @mobile_device.revoke!(reason: "website_sign_out")
      redirect_to users_mobile_devices_path, notice: "#{@mobile_device.name.presence || 'The phone'} has been signed out."
    end
  end
end
