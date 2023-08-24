class CapitalRemittanceNotification < BaseNotification
  # Add your delivery methods
  deliver_by :email, mailer: "CapitalRemittancesMailer", method: :email_method, format: :email_data

  # Add required params
  param :capital_remittance
  param :email_method

  def email_method
    params[:email_method]
  end

  def email_data
    {
      user_id: recipient.id,
      capital_remittance_id: params[:capital_remittance].id
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @capital_remittance = params[:capital_remittance]
    params[:msg] || "Capital Call by #{@capital_remittance.entity.name} : #{@capital_remittance.capital_call.name}"
  end

  def url
    capital_remittance_path(id: params[:capital_remittance].id)
  end
end
