class SecondarySaleNotification < BaseNotification
  # Add your delivery methods
  if Rails.env.test?
    deliver_by :email, mailer: "SecondarySaleMailer", method: :email_method, format: :email_data
  else
    deliver_by :email, mailer: "SecondarySaleMailer", method: :email_method, format: :email_data, delay: :email_delay
  end
  # Add required params
  param :secondary_sale
  param :email_method

  def email_data
    {
      user_id: recipient.id,
      entity_id: params[:entity_id],
      secondary_sale_id: params[:secondary_sale].id
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @secondary_sale = params[:secondary_sale]
    params[:msg] || "SecondarySale: #{@secondary_sale}"
  end

  def url
    secondary_sale_path(id: params[:secondary_sale].id)
  end
end
