class AmlReportsController < ApplicationController
  before_action :set_aml_report, only: %i[show]
  after_action :verify_authorized

  def index
    authorize(AmlReport)
    @aml_reports = policy_scope(AmlReport)
    @aml_reports = @aml_reports.where(investor_kyc_id: params[:investor_kyc_id]) if params[:investor_kyc_id].present?
    @bread_crumbs = if params[:investor_kyc_id].present?
                      { KYCs: investor_kycs_path, "#{@aml_reports.first.investor_kyc.full_name}": investor_kyc_path(@aml_reports.first.investor_kyc), 'AML Reports': '' }
                    else
                      { 'AML Reports': '' }
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
