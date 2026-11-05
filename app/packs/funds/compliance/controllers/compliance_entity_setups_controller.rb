# ② Setup: input mappings, per-fund figures, dated reference lists, owner, monitoring (H17, X15, X16, E14).
class ComplianceEntitySetupsController < ApplicationController
  before_action :set_setup

  def show
    authorize @setup
    @inputs = ComplianceInputs.for(current_user.entity)
  end

  def update
    authorize @setup
    result = ComplianceSetupUpdate.call(setup: @setup, params: setup_params, user: current_user)
    if result.success?
      redirect_to compliance_entity_setup_path, notice: result.notice
    else
      @inputs = ComplianceInputs.for(current_user.entity)
      flash.now[:alert] = result.error
      render :show, status: :unprocessable_content
    end
  end

  private

  def set_setup
    @setup = ComplianceEntitySetup.for(current_user.entity)
  end

  # owner_id is checked same-firm by the model; entity_id is never permitted
  def setup_params
    params.expect(compliance_entity_setup: [:owner_id, :monitoring_enabled, :time_zone,
                                            { mappings: {}, fund_figures: {}, reference_lists: {} }])
  end
end
