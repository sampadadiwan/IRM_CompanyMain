# To deliver this notification:
#
# ExpressionOfInterestNotification.with(expression_of_interest_id: @expression_of_interest.id, msg: "Please View").deliver_later(current_user)
# ExpressionOfInterestNotification.with(expression_of_interest_id: @expression_of_interest.id, msg: "Please View").deliver(current_user)

class ExpressionOfInterestNotification < Noticed::Base
  # Add your delivery methods
  deliver_by :database
  deliver_by :email, mailer: "ExpressionOfInterestMailer", method: :notify_approved, format: :email_data
  deliver_by :whats_app, class: "DeliveryMethods::WhatsApp"
  deliver_by :user_alerts, class: "DeliveryMethods::UserAlerts"

  # Add required params
  param :expression_of_interest_id

  def email_data
    {
      user_id: recipient.id,
      expression_of_interest_id: params[:expression_of_interest_id]
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @expression_of_interest = ExpressionOfInterest.find(params[:expression_of_interest_id])
    params[:msg] || "Expression Of Interest Approved: #{@expression_of_interest.investment_opportunity.company_name}"
  end

  def url
    expression_of_interest_path(id: params[:expression_of_interest_id])
  end
end
