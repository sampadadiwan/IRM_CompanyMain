# ② Setup: input mappings, per-fund figures, dated reference lists, owner, monitoring (H17, X15, X16, E14)
# and the AI-drafting switch (X41).
class ComplianceEntitySetupsController < ApplicationController
  include ComplianceCrumbs

  before_action :set_setup

  def show
    authorize @setup
    @inputs = ComplianceInputs.for(current_user.entity)
    # ⑩ Getting started steps 1 and 4 land here: owner choices and the lists the attached checks read
    @owner_choices = User.where(entity_id: current_user.entity_id, active: true).order(:first_name).select { |u| ComplianceAccess.viewer?(u) }
    @list_keys = (ComplianceGettingStarted.new(current_user.entity, current_user).needed_lists + @setup.reference_lists_hash.keys).uniq
    # The Compliance hub's lazy Setup pane (R170): this page's content inside the hub frame
    render_hub_pane(:setup, "compliance_entity_setups/show") if hub_frame_request?(:setup)
  end

  def update
    authorize @setup
    result = ComplianceSetupUpdate.call(setup: @setup, params: setup_params, user: current_user)
    if result.success?
      redirect_to compliance_entity_setup_path, notice: result.notice
    else
      @inputs = ComplianceInputs.for(current_user.entity)
      @owner_choices = User.where(entity_id: current_user.entity_id, active: true).order(:first_name).select { |u| ComplianceAccess.viewer?(u) }
      @list_keys = (ComplianceGettingStarted.new(current_user.entity, current_user).needed_lists + @setup.reference_lists_hash.keys).uniq
      flash.now[:alert] = result.error
      render :show, status: :unprocessable_content
    end
  end

  private

  def set_setup
    @setup = ComplianceEntitySetup.for(current_user.entity)
    compliance_crumbs(["Setup", nil])
  end

  # owner_id is checked same-firm by the model; entity_id is never permitted
  def setup_params
    params.expect(compliance_entity_setup: [:owner_id, :monitoring_enabled, :ai_drafting, :time_zone,
                                            { mappings: {}, fund_figures: {}, reference_lists: {}, ai_reading: {} }])
  end
end
