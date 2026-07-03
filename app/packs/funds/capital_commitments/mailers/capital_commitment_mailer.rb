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

  def custom_notification_documents_owner
    @capital_commitment
  end

  # We can add more specific notification methods here if needed
  # For now, adhoc_notification from ApplicationMailer is used by FundCommitmentNotifier
end
