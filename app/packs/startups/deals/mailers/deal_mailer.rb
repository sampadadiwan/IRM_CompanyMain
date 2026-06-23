class DealMailer < ApplicationMailer
  append_view_path "app/packs/startups/deals/mailers/views"

  PLACEHOLDERS = ApplicationMailer::PLACEHOLDERS.merge(
    "deal_name" => ->(m) { m.instance_variable_get(:@deal)&.name },
    "investor_name" => ->(m) { m.instance_variable_get(:@deal_investor)&.investor&.name }
  ).freeze

  before_action :set_deal_data

  def set_deal_data
    @deal_investor = params[:record] || DealInvestor.find_by(id: params[:record_id]) || DealInvestor.find_by(id: @notification&.params&.dig(:record_id))
    @deal = @deal_investor&.deal
    @activity_title = params[:activity_title] || @notification&.params&.dig(:activity_title)

    # If there's a custom_notification_id passed (either directly or via notification params), load it
    custom_notification_id = params[:custom_notification_id]
    custom_notification_id ||= @notification.params[:custom_notification_id] if @notification&.params
    @custom_notification = CustomNotification.find(custom_notification_id) if custom_notification_id.present?
  end

  # This mailer handles deal-related notifications that don't use CustomNotification templates.
  # For move notifications, it provides the default content.

  def deal_activity_move
    # Recipient and defaults are set by setup_defaults in ApplicationMailer
    # based on the notification's recipient and params.

    mail(
      to: @to,
      from: @from,
      cc: @cc,
      reply_to: @reply_to,
      subject: "Deal Update: #{@deal.name} moved to stage: #{@activity_title}"
    )
  end
end
