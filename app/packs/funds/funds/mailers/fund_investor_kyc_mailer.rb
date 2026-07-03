# FundInvestorKycMailer sends a Fund's adhoc CustomNotification scoped to an
# InvestorKyc rather than a CapitalCommitment. It exists as a parallel to
# CapitalCommitmentMailer (see that file) rather than reusing InvestorKycMailer,
# because InvestorKycMailer#set_kyc resolves @custom_notification via
# investor_kyc.entity.custom_notification(..., for_type: "InvestorKyc") — a lookup
# against Entity-owned notifications for the pre-existing KYC-completion email
# flow (notify_kyc_required, etc.), which is a totally different record space
# from our Fund-owned (owner_type: "Fund") adhoc notifications. Reusing it here
# would silently resolve the wrong CustomNotification (or none at all).
class FundInvestorKycMailer < ApplicationMailer
  helper ApplicationHelper
  helper CurrencyHelper

  # These merge into ApplicationMailer::PLACEHOLDERS, becoming available as
  # {{investor_name}}, {{fund_name}}, {{kyc_full_name}} tokens inside a
  # CustomNotification body that is NOT using the raw-ERB ("Dynamic Template") mode.
  # Every lambda reads from @investor_kyc rather than @capital_commitment, since
  # this mailer may represent several commitments collapsed into one KYC-based email.
  PLACEHOLDERS = ApplicationMailer::PLACEHOLDERS.merge(
    "investor_name" => ->(m) { m.instance_variable_get(:@investor_kyc)&.investor_name },
    "fund_name" => ->(m) { m.instance_variable_get(:@fund)&.name },
    "kyc_full_name" => ->(m) { m.instance_variable_get(:@investor_kyc)&.full_name }
  ).freeze

  # Runs after ApplicationMailer's own before_actions (setup_defaults, tag_for_bounce_tracking),
  # so @notification (the live Noticed::Notification, when this is a real send rather than a
  # preview) is already set by the time we get here.
  before_action :set_investor_kyc

  def set_investor_kyc
    # The KYC record this email is about. Because one InvestorKyc can back many
    # CapitalCommitments (possibly across several funds), this is intentionally
    # NOT derived from any single commitment — FundNotificationJob passes the id directly.
    @investor_kyc = InvestorKyc.find(params[:investor_kyc_id])

    # fund_id is passed through explicitly (rather than derived from @investor_kyc,
    # which has no single owning fund) so we still know which Fund triggered this send —
    # used for the {{fund_name}}-adjacent context and kept for parity with
    # CapitalCommitmentMailer's @fund ivar.
    @fund = Fund.find(params[:fund_id]) if params[:fund_id]

    # Same direct-lookup pattern as CapitalCommitmentMailer#set_capital_commitment:
    # find the CustomNotification by id straight away, no entity/for_type scoping —
    # this is what makes this mailer safe where InvestorKycMailer's own lookup is not.
    custom_notification_id = params[:custom_notification_id]
    @custom_notification = CustomNotification.find(custom_notification_id) if custom_notification_id.present?
    @subject = @custom_notification&.subject
  end

  # Defined explicitly (rather than relying on ApplicationMailer's generic
  # adhoc_notification) so this is its own distinct email_method — "adhoc_kyc_notification" —
  # discoverable by CustomNotification#email_methods via instance_methods(false)
  # (see custom_notification.rb) without any manual list-wrangling. This is what lets it
  # slot into the existing "For Notification" dropdown and placeholder picker for free,
  # instead of needing a separate side-channel field to distinguish it from
  # CapitalCommitmentMailer's own "adhoc_notification".
  def adhoc_kyc_notification
    send_mail(subject: @custom_notification.subject, template_path: 'application_mailer', template_name: 'adhoc_notification')
  end

  private

  # Override needed for the SAME reason CapitalCommitmentMailer overrides this: the base
  # ApplicationMailer default (@notification&.model) is correct for real sends (where
  # @notification.model IS @investor_kyc, since FundInvestorKycNotifier passes record: kyc),
  # but @notification is nil during preview (WithEmailPreview builds no Noticed::Notification —
  # see application_mailer.rb's own comment on this method). Without this override, previewing
  # an adhoc_kyc_notification would silently show zero attachments even when attachment_names
  # matches real documents on @investor_kyc, misleading admins about what will actually send.
  def custom_notification_documents_owner
    @investor_kyc
  end
end
