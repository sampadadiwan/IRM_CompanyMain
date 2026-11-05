# ① Draft editing, test run (preview mode — nothing stored, R37) and publishing with its gates
# (X8, X9, X10, X50, X51). Locked CapHive packs are never customer-editable (X13, X55).
class CompliancePackVersionsController < ApplicationController
  before_action :set_version

  def show
    authorize @version
  end

  # The whole definition is edited as one validated JSON document (size-capped)
  def update
    authorize @version
    raw = params.require(:compliance_pack_version).fetch(:definition, "").to_s
    return render_error("Definition is too large") if raw.bytesize > 256.kilobytes

    @version.definition = JSON.parse(raw)
    if @version.save
      redirect_to compliance_pack_version_path(@version), notice: "Draft saved"
    else
      render_error(@version.errors.full_messages.to_sentence)
    end
  rescue JSON::ParserError
    render_error("Definition is not valid JSON")
  end

  # Preview the draft on a fund: CapHive drafts on the demo entity or a customer that granted support access (H4, E7, X11)
  def test_run
    authorize @version
    fund = test_fund
    raise Pundit::NotAuthorizedError, "No consent for a test run" if fund.nil?

    @preview = CompliancePreview.call(version: @version, fund:, classification: params[:classification])
    @version.mark_tested!(current_user)
    render :show
  end

  def publish
    authorize @version
    if @version.publish!(user: current_user, attrs: publish_params.to_h.symbolize_keys)
      CompliancePublishNotices.call(@version)
      redirect_to compliance_pack_path(@version.compliance_pack), notice: "Published #{@version.label}"
    else
      render_error(@version.errors.full_messages.to_sentence)
    end
  end

  private

  def set_version
    @version = CompliancePackVersion.where(compliance_pack_id: policy_scope(CompliancePack).select(:id)).find_by(id: params[:id]) || raise(Pundit::NotAuthorizedError)
  end

  def publish_params
    params.expect(compliance_pack_version: %i[effective_from applicability applicability_date transition_ends_on
                                              allows_early_adoption counsel_reviewer counsel_reviewed_on])
  end

  def test_fund
    fund = Fund.find_by(id: params[:fund_id])
    return nil if fund.nil?

    CompliancePreview.allowed_fund?(current_user, @version, fund) ? fund : nil
  end

  def render_error(message)
    flash.now[:alert] = message
    render :show, status: :unprocessable_content
  end
end
