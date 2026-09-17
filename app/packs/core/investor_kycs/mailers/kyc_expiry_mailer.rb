class KycExpiryMailer < ApplicationMailer
  def expiry_alert
    @investor_kyc = InvestorKyc.find(params[:investor_kyc_id])
    @issues = params[:issues]
    @entity = Entity.find(params[:entity_id])

    # ApplicationMailer#setup_defaults only applies the sandbox redirect when a
    # user_id param is present (@user-keyed). This mailer addresses all active
    # employees instead of one user, so it must honor the sandbox setting itself
    # — otherwise sandboxed entities would email real employee addresses.
    employee_emails = @entity.employees.active.pluck(:email).join(",")
    @to = @entity.entity_setting&.sandbox ? @entity.entity_setting.sandbox_emails : employee_emails

    # No recipients (e.g. entity with no active employees): return without
    # calling mail() — raising here would make the Sidekiq delivery job retry a
    # permanently-failing send. The agent also guards this, belt-and-braces.
    if @to.blank?
      Rails.logger.info("[KycExpiryMailer] No recipients for expiry alert (entity #{@entity.id}) — skipping send")
      return
    end

    subject = "KYC Expiry Alert — #{@investor_kyc.full_name}"
    mail(from: @from, to: @to, cc: @cc, subject:)
  end
end
