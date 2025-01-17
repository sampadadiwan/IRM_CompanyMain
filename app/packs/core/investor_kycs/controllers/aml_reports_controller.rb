class AmlReportsController < ApplicationController
  before_action :set_aml_report, only: %i[show]
  after_action :verify_authorized

  def show; end

  private

  def set_aml_report
    @aml_report = AmlReport.find(params[:id])
    @bread_crumbs = { KYCs: investor_kycs_path, "#{@aml_report.investor_kyc.full_name}": investor_kyc_path(@aml_report.investor_kyc), 'AML Report': aml_report_path(@aml_report) }
    authorize @aml_report
  end
end
