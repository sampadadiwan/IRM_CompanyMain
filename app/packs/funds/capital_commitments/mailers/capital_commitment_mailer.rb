class CapitalCommitmentMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  PLACEHOLDERS = ApplicationMailer::PLACEHOLDERS.merge(
    "investor_name" => ->(m) { m.instance_variable_get(:@capital_commitment)&.investor&.name },
    "fund_name" => ->(m) { m.instance_variable_get(:@fund)&.name },
    "committed_amount" => ->(m) { m.instance_variable_get(:@capital_commitment)&.committed_amount&.format },
    "kyc_full_name" => ->(m) { m.instance_variable_get(:@capital_commitment)&.investor_kyc&.full_name },
    "folio_id" => ->(m) { m.instance_variable_get(:@capital_commitment)&.folio_id }
  ).freeze

  before_action :set_capital_commitment

  def set_capital_commitment
    @capital_commitment = CapitalCommitment.find(params[:capital_commitment_id])
    @fund = @capital_commitment.fund
    @investor_kyc = @capital_commitment.investor_kyc
    custom_notification_id = params[:custom_notification_id]
    custom_notification_id ||= @notification.params[:custom_notification_id] if @notification&.params
    @custom_notification = CustomNotification.find(custom_notification_id) if custom_notification_id.present?
    @subject = @custom_notification&.subject || @notification&.message
  end

  # We can add more specific notification methods here if needed
  # For now, adhoc_notification from ApplicationMailer is used by FundCommitmentNotifier

  private

  # private, like custom_notification_documents_owner below: helper_method exposes it to the
  # view via #send regardless of visibility, and public would leak it into
  # CustomNotification#email_methods's instance_methods(false) scan as a bogus dropdown entry.
  def adhoc_notification_link
    { label: 'View Commitment', url: capital_commitment_url(@capital_commitment, subdomain: @capital_commitment.entity.sub_domain) }
  end

  # private: this is an internal resolver for attach_custom_notification_documents, not a
  # mailer action — public would leak it into CustomNotification#email_methods (which reads
  # instance_methods(false) to populate the "For Notification" dropdown).
  def custom_notification_documents_owner
    @capital_commitment
  end
end
