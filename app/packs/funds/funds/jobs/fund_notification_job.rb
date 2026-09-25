class FundNotificationJob < ApplicationJob
  queue_as :default

  # investor_kyc_ids is only ever populated when custom_notification.email_method ==
  # "adhoc_kyc_notification" (the "Select Investor KYCs to Notify" picker); it's simply
  # ignored otherwise.
  #
  # triggered_by_user_id (optional) is threaded straight through to each recipient's
  # notifier — see Fund#adhoc_notification.
  def perform(fund_id, custom_notification_id, commitment_ids = nil, investor_kyc_ids = nil, triggered_by_user_id = nil)
    fund = Fund.find(fund_id)
    custom_notification = CustomNotification.find(custom_notification_id)

    # "adhoc_kyc_notification" is FundInvestorKycMailer's own explicitly-defined email_method
    # (see that class) — every other email_method (including "adhoc_fund_notification", formerly
    # "adhoc_notification", and any historical rows not yet migrated) keeps going through the
    # CapitalCommitment path, unchanged.
    if custom_notification.email_method == "adhoc_kyc_notification"
      perform_by_investor_kyc(fund, custom_notification, investor_kyc_ids, triggered_by_user_id)
    else
      perform_by_capital_commitment(fund, custom_notification, commitment_ids, triggered_by_user_id)
    end
  end

  private

  # Historical behavior: one email per (CapitalCommitment, qualifying recipient) pair.
  def perform_by_capital_commitment(fund, custom_notification, commitment_ids, triggered_by_user_id)
    # nil/empty means all commitments; otherwise filter to the selected subset
    commitments = commitment_ids.present? ? fund.capital_commitments.where(id: commitment_ids) : fund.capital_commitments

    # Size-check what each commitment would be sent before enqueuing any of it. Checked per
    # commitment rather than once, because attachment_names resolves against each commitment's
    # own documents — two investors on the same send can legitimately receive different files.
    # Returns rather than raises so Sidekiq does not retry a batch that cannot succeed.
    blocked = NotificationAttachmentPreflight.batch_error_message(
      commitments, custom_notification,
      context: "Cannot send \"#{custom_notification.subject}\" for #{fund.name}",
      # A commitment nobody would be emailed for must not block the fund's whole send. Not
      # expressible in SQL — notification_users runs a Pundit policy per contact.
      skip_if: ->(commitment) { commitment.investor.notification_users(commitment).empty? }
    )
    if blocked.present?
      NotificationAttachmentPreflight.report_blocked_send(blocked, entity_id: fund.entity_id, user_id: triggered_by_user_id,
                                                                   subject: "Fund notification not sent")
      return
    end

    commitments.find_each do |commitment|
      investor = commitment.investor
      # recipients will be the capital_commitment.investor.notification_users
      recipients = investor.notification_users(commitment)

      recipients.each do |recipient|
        FundCommitmentNotifier.with(
          record: commitment,
          entity_id: fund.entity_id,
          custom_notification_id: custom_notification.id,
          email_method: custom_notification.email_method,
          triggered_by_user_id: triggered_by_user_id
        ).deliver_later(recipient)
      end
    end
  end

  # New: one email per unique InvestorKyc, regardless of how many CapitalCommitments
  # in this fund share that KYC record. fund.investor_kycs is has_many :through
  # capital_commitments, so it naturally yields one row per commitment — .distinct
  # collapses that back down to one row per KYC, which is exactly the dedup the
  # admin picker (and this job) both rely on: an investor with several commitments
  # sharing one KYC still only gets a single email.
  def perform_by_investor_kyc(fund, custom_notification, investor_kyc_ids, triggered_by_user_id)
    # Scoped to fund.investor_kycs (not a bare InvestorKyc.where(id:...)) so a
    # company_admin authorized to trigger notifications for THIS fund can't submit ids
    # belonging to another fund/entity's InvestorKyc and leak this fund's notification
    # content/attachments to unrelated investors — mirrors how commitment_ids is scoped
    # to fund.capital_commitments below. .distinct is still needed here even with an
    # id filter, since the same KYC can join back to multiple matching commitment rows.
    kycs = investor_kyc_ids.present? ? fund.investor_kycs.where(id: investor_kyc_ids).distinct : fund.investor_kycs.distinct

    # Same size preflight as the capital-commitment path above — attachment_names resolves
    # against each InvestorKyc's own documents here (FundInvestorKycMailer overrides
    # custom_notification_documents_owner), so it is checked per KYC and stops the whole run.
    blocked = NotificationAttachmentPreflight.batch_error_message(
      kycs, custom_notification,
      context: "Cannot send \"#{custom_notification.subject}\" for #{fund.name}",
      # Same as the commitment path: a KYC with no resolvable recipients is not part of this send.
      skip_if: ->(kyc) { kyc.investor.notification_users(kyc).empty? }
    )
    if blocked.present?
      NotificationAttachmentPreflight.report_blocked_send(blocked, entity_id: fund.entity_id, user_id: triggered_by_user_id,
                                                                   subject: "Fund notification not sent")
      return
    end

    kycs.find_each do |kyc|
      # notification_users is generic (Investor#notification_users, app/packs/core/investors/models/investor.rb) —
      # it resolves InvestorKycPolicy via Pundit for an InvestorKyc argument with no special-casing needed,
      # the same way it resolves CapitalCommitmentPolicy for a commitment above.
      recipients = kyc.investor.notification_users(kyc)

      recipients.each do |recipient|
        FundInvestorKycNotifier.with(
          record: kyc,
          entity_id: fund.entity_id,
          fund_id: fund.id,
          custom_notification_id: custom_notification.id,
          email_method: custom_notification.email_method,
          triggered_by_user_id: triggered_by_user_id
        ).deliver_later(recipient)
      end
    end
  end
end
