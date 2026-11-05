# ⑨ Register export for a period (Excel). Built on request and streamed — no stored file or link that
# another user could open (X36); rows limited to funds the user can see (E47).
class ComplianceExportsController < ApplicationController
  def create
    authorize :compliance_export, :create?
    from = Date.parse(params[:from].to_s)
    to = Date.parse(params[:to].to_s)
    data = ComplianceRegisterExport.call(user: current_user, from:, to:, fund_ids: Array(params[:fund_ids]).compact_blank.map(&:to_i))
    send_data data, filename: "compliance_register_#{from.iso8601}_#{to.iso8601}.xlsx",
                    type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  rescue Date::Error
    redirect_back_or_to(compliance_home_path, alert: "Choose a period")
  end
end
