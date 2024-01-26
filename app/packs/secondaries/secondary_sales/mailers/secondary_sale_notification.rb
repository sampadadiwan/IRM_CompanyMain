class SecondarySaleNotification < BaseNotification
  # Add required params
  param :secondary_sale
  param :email_method

  def mailer_name
    SecondarySaleMailer
  end

  def email_data
    {
      notification_id: record.id,
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
