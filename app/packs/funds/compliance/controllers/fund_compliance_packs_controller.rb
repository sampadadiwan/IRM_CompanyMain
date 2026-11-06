# ② The setup grid (packs per fund), attaching a pack (H11, X14, X23), the fund's compliance dashboard,
# Run now (E18) and the read-only version preview (H48, E89). Re-running a past date is refused (X65).
class FundCompliancePacksController < ApplicationController
  include ComplianceCrumbs

  before_action :set_fund_pack, only: %i[show run_now preview rerun]

  # R175 / E203: the fund × pack grid is the Home funds grid (compliance_shared/_funds_grid), which also
  # attaches from any row — one view instead of two. Old links and bookmarks land there.
  def index
    authorize FundCompliancePack
    # A redirect that reads no records — the grid it lands on is policy-scoped in ComplianceHomeController
    skip_policy_scope
    redirect_to compliance_home_path(tab: ComplianceHub.pane_id(:home))
  end

  # The attach form in the remote modal, opened from a grid row (fund chosen), the grid header, a pack's
  # page (pack chosen) or a fund's empty Compliance tab. Only the user's own visible funds and attachable
  # packs are offered; an id from another firm simply is not found (X23).
  def new
    authorize FundCompliancePack, :new?
    @funds = Fund.where(id: ComplianceAccess.fund_ids(current_user)).order(:name)
    # versions preloaded: attachable? reads the latest published version per pack (no query per pack)
    @packs = policy_scope(CompliancePack).includes(:versions).reject(&:retired?).select(&:attachable?)
    @fund = @funds.find_by(id: params[:fund_id])
    @pack = @packs.detect { |p| p.id.to_s == params[:compliance_pack_id].to_s }
    @attached_names = @fund ? policy_scope(FundCompliancePack).active.where(fund_id: @fund.id).includes(:compliance_pack).map(&:pack_name) : []
  end

  # The fund page's Compliance tab (lazy turbo frame): the same dashboard as #show, for one fund
  def fund_tab
    authorize FundCompliancePack, :index?
    @fund = Fund.where(id: ComplianceAccess.fund_ids(current_user)).find_by(id: params[:fund_id]) || raise(Pundit::NotAuthorizedError)
    @dashboard = ComplianceDashboard.new(@fund, current_user)
    render layout: false
  end

  def create
    fund = Fund.where(entity_id: current_user.entity_id).find_by(id: attach_params[:fund_id])
    pack = policy_scope(CompliancePack).find_by(id: attach_params[:compliance_pack_id])
    @fund_pack = FundCompliancePack.new(entity_id: current_user.entity_id, fund:, compliance_pack: pack,
                                        classification: attach_params[:classification].presence || prefill(fund, pack))
    # X23: a fund of another firm is never found above, so this is refused
    raise Pundit::NotAuthorizedError if fund.nil? || pack.nil?

    authorize @fund_pack
    # Back to the funds grid, where the row now shows the pack (E203)
    home = compliance_home_path(tab: ComplianceHub.pane_id(:home))
    if @fund_pack.save
      redirect_to home, notice: "#{pack.name} attached to #{fund.name}"
    else
      redirect_to home, alert: @fund_pack.errors.full_messages.to_sentence
    end
  end

  # The fund's dashboard: latest result per check, run health, version banner
  def show
    authorize @fund_pack
    @dashboard = ComplianceDashboard.new(@fund_pack.fund, current_user)
    # A pack tab's lazy pane: only that pack's latest results, in its frame
    if params[:pane] == "results" && turbo_frame_request?
      return render partial: "fund_compliance_packs/results_frame",
                    locals: { fund_pack: @fund_pack, results: @dashboard.latest_results[@fund_pack.id] || [] }
    end

    compliance_fund_crumbs(@fund_pack.fund, [@fund_pack.pack_name, nil])
  end

  def run_now
    authorize @fund_pack
    ComplianceFundRunJob.perform_later(@fund_pack.fund_id, Time.current.in_time_zone(setup_time_zone).to_date.iso8601, "run_now")
    notice = "Running — results update when the run finishes. Refresh in a minute."
    respond_to do |format|
      format.turbo_stream do
        @notice = notice
        render "compliance_shared/flash"
      end
      format.html { redirect_to fund_compliance_pack_path(@fund_pack), notice: }
    end
  end

  def preview
    authorize @fund_pack
    version = @fund_pack.compliance_pack.versions.find_by(id: params[:version_id]) || raise(Pundit::NotAuthorizedError)
    @preview = CompliancePreview.call(version:, fund: @fund_pack.fund, classification: @fund_pack.classification)
    @dashboard = ComplianceDashboard.new(@fund_pack.fund, current_user)
    compliance_fund_crumbs(@fund_pack.fund, [@fund_pack.pack_name, fund_compliance_pack_path(@fund_pack)], ["Preview #{version.label}", nil])
    render :show
  end

  # X65: past dates are never re-run
  def rerun
    authorize ComplianceResult.new(fund_compliance_pack: @fund_pack, entity_id: @fund_pack.entity_id), :rerun?
  end

  private

  def set_fund_pack
    @fund_pack = policy_scope(FundCompliancePack).find_by(id: params[:id]) || raise(Pundit::NotAuthorizedError)
  end

  def attach_params
    params.expect(fund_compliance_pack: %i[fund_id compliance_pack_id classification])
  end

  # H12/E11: the fund's Category pre-fills the classification when the pack defines it
  def prefill(fund, pack)
    return nil unless fund && pack

    version = pack.version_for_new_attachment(fund)
    version&.classifications&.include?(fund.category) ? fund.category : nil
  end

  def setup_time_zone
    ComplianceEntitySetup.for(current_user.entity).time_zone
  end
end
