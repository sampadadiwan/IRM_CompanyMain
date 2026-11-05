# ② The setup grid (packs per fund), attaching a pack (H11, X14, X23), the fund's compliance dashboard,
# Run now (E18) and the read-only version preview (H48, E89). Re-running a past date is refused (X65).
class FundCompliancePacksController < ApplicationController
  before_action :set_fund_pack, only: %i[show run_now preview rerun]

  def index
    authorize FundCompliancePack
    @funds = Fund.where(id: ComplianceAccess.fund_ids(current_user)).order(:name)
    @fund_packs = policy_scope(FundCompliancePack).includes(:compliance_pack, :compliance_pack_version).group_by(&:fund_id)
    @packs = policy_scope(CompliancePack).reject(&:retired?)
  end

  def create
    fund = Fund.where(entity_id: current_user.entity_id).find_by(id: attach_params[:fund_id])
    pack = policy_scope(CompliancePack).find_by(id: attach_params[:compliance_pack_id])
    @fund_pack = FundCompliancePack.new(entity_id: current_user.entity_id, fund:, compliance_pack: pack,
                                        classification: attach_params[:classification].presence || prefill(fund, pack))
    # X23: a fund of another firm is never found above, so this is refused
    raise Pundit::NotAuthorizedError if fund.nil? || pack.nil?

    authorize @fund_pack
    if @fund_pack.save
      redirect_to fund_compliance_packs_path, notice: "#{pack.name} attached to #{fund.name}"
    else
      redirect_to fund_compliance_packs_path, alert: @fund_pack.errors.full_messages.to_sentence
    end
  end

  # The fund's dashboard: latest result per check, run health, version banner
  def show
    authorize @fund_pack
    @dashboard = ComplianceDashboard.new(@fund_pack.fund, current_user)
  end

  def run_now
    authorize @fund_pack
    ComplianceFundRunJob.perform_later(@fund_pack.fund_id, Time.current.in_time_zone(setup_time_zone).to_date.iso8601, "run_now")
    redirect_to fund_compliance_pack_path(@fund_pack), notice: "Running…"
  end

  def preview
    authorize @fund_pack
    version = @fund_pack.compliance_pack.versions.find_by(id: params[:version_id]) || raise(Pundit::NotAuthorizedError)
    @preview = CompliancePreview.call(version:, fund: @fund_pack.fund, classification: @fund_pack.classification)
    @dashboard = ComplianceDashboard.new(@fund_pack.fund, current_user)
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
