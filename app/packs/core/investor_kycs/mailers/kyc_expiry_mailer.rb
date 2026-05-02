class KycExpiryMailer < ApplicationMailer
  def expiry_alert
    @investor_kyc = InvestorKyc.find(params[:investor_kyc_id])
    @issues = params[:issues]
    @entity = Entity.find(params[:entity_id])

    @to = @entity.employees.active.pluck(:email).join(",")
    subject = "KYC Expiry Alert — #{@investor_kyc.full_name}"
    mail(from: @from, to: @to, cc: @cc, subject:)
  end
end
