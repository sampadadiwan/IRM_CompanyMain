class CapitalCommitmentMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper

  before_action :set_capital_commitment

  def set_capital_commitment
    @capital_commitment = CapitalCommitment.find(params[:capital_commitment_id])
    @fund = @capital_commitment.fund
    @investor_kyc = @capital_commitment.investor_kyc
    @custom_notification = CustomNotification.find(@notification.params[:custom_notification_id]) if @notification&.params&.dig(:custom_notification_id).present?
    @subject = @custom_notification&.subject || @notification&.message
  end

  # We can add more specific notification methods here if needed
  # For now, adhoc_notification from ApplicationMailer is used by FundCommitmentNotifier
end
