# Edit an open-ended fund's terms (forward-only). A fund's type is chosen when it is created (New Fund)
# and can't be changed, so there is no make-evergreen or switch-back here.
# Worked examples E6, X4, X5 — openspec/changes/evergreen-fund-on-create/design.md#worked-examples;
# H2, E6, X2, X3 — openspec/changes/open-ended-funds/design.md#worked-examples
module Evergreen
  class SettingsController < BaseController
    include EvergreenSettingParams

    before_action :require_evergreen_fund

    def show
      @setting = evergreen_setting
      authorize @setting
    end

    # Changes apply to orders received and dealing dates confirmed after now (E6)
    def update
      @setting = evergreen_setting
      authorize @setting
      if @setting.update(evergreen_setting_attributes_for_update)
        # Open dealing dates follow a changed payment timing (confirmed ones keep theirs), so orders,
        # confirm and settlement read one value (review finding)
        @fund.dealing_dates.where(status: "open").where.not(payment_timing: @setting.payment_timing)
             .update_all(payment_timing: @setting.payment_timing, updated_at: Time.current)
        redirect_to evergreen_settings_path(@fund), notice: "Settings saved"
      else
        flash.now[:alert] = @setting.errors.full_messages.to_sentence
        render :show, status: :unprocessable_entity
      end
    rescue EvergreenFormParsing::BadDates => e
      flash.now[:alert] = e.message
      render :show, status: :unprocessable_entity
    end

    private

    # X4: a closed-ended fund has no evergreen settings, and can't be given any
    def require_evergreen_fund
      return if @fund.evergreen?

      redirect_to fund_path(@fund), alert: EvergreenSettingParams::TYPE_FIXED_MESSAGE
    end
  end
end
