class AmlReportsController < ApplicationController
  before_action :set_aml_report, only: %i[show]
  after_action :verify_authorized

  def index
    authorize(AmlReport)
    @aml_reports = policy_scope(AmlReport)
    @bread_crumbs = { 'AML Reports': '' }

    if params[:investor_kyc_id].present?
      @aml_reports = @aml_reports.where(investor_kyc_id: params[:investor_kyc_id])
      # The breadcrumb names the *parent* KYC, so load the KYC itself rather than deriving it
      # from @aml_reports.first. The policy scope here is where(entity_id: user.entity_id),
      # which can legitimately come back empty for a user who is still allowed to open the KYC
      # (investor-entity user, group-company parent, support session) - .first was then nil and
      # every such click 500ed (incident 45847776).
      # find_by, not find: an unknown id should degrade to the plain crumb and an empty list,
      # not 404 a page that is otherwise valid.
      investor_kyc = InvestorKyc.find_by(id: params[:investor_kyc_id])
      # Gate on show? so the crumb never leaks a KYC's full_name to someone who may not open it.
      if investor_kyc && policy(investor_kyc).show?
        @bread_crumbs = { KYCs: investor_kycs_path,
                          "#{investor_kyc.full_name}": investor_kyc_path(investor_kyc),
                          'AML Reports': '' }
      end
    end

    @aml_reports = @aml_reports.order(created_at: :desc)
  end

  def show; end

  private

  def set_aml_report
    @aml_report = AmlReport.find(params[:id])
    @bread_crumbs = { KYCs: investor_kycs_path, "#{@aml_report.investor_kyc.full_name}": investor_kyc_path(@aml_report.investor_kyc), 'AML Report': aml_report_path(@aml_report) }
    authorize @aml_report
  end
end
