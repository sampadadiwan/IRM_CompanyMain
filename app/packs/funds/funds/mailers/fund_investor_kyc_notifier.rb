# FundInvestorKycNotifier is the Noticed::Event that fans out a Fund's adhoc
# CustomNotification per InvestorKyc, mirroring FundCommitmentNotifier
# (app/packs/funds/capital_commitments/mailers/fund_commitment_notifier.rb) almost
# line for line — the only real difference is what `record` is (an InvestorKyc
# here, a CapitalCommitment there) and how from_email is resolved (InvestorKyc has
# no single owning fund, so the triggering fund's id is threaded through params
# instead of read off `record.fund`).
class FundInvestorKycNotifier < BaseNotifier
  required_param :email_method
  required_param :custom_notification_id

  # Tells BaseNotifier's `deliver_by :email` config which mailer class to use.
  def mailer_name(_notification = nil)
    FundInvestorKycMailer
  end

  # Params handed to the mailer action as `params[...]` — this is how
  # FundInvestorKycMailer#set_investor_kyc gets investor_kyc_id/fund_id/etc.
  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      # Passed through explicitly since InvestorKyc isn't scoped to one fund
      # (has_many :funds, through: :capital_commitments) — we still want to know
      # which fund's "Send Notification" click triggered this particular batch.
      fund_id: params[:fund_id],
      investor_kyc_id: record.id,
      investor_id: record.investor_id,
      # Mirrors FundCommitmentNotifier's record.fund.custom_fields.from_email,
      # just resolved via the explicit fund_id instead of record.fund.
      from_email: params[:fund_id] ? Fund.find(params[:fund_id]).custom_fields.from_email : nil,
      custom_notification_id: params[:custom_notification_id]
    }
  end

  # In-app (Noticed::Event) representation — used by the notifications table/UI,
  # separate from the actual outgoing email built by the mailer above.
  notification_methods do
    def message
      @investor_kyc = record
      # Direct CustomNotification.find by id — deliberately NOT going through
      # investor_kyc.entity.custom_notification(...), which is scoped to a
      # different (Entity-owned) notification concept. See FundInvestorKycMailer
      # for the full explanation.
      @custom_notification ||= CustomNotification.find(params[:custom_notification_id])
      params[:msg] || "Notification for: #{@investor_kyc}"
    end

    def url
      investor_kyc_url(record, sub_domain: record.entity.sub_domain)
    end
  end
end
