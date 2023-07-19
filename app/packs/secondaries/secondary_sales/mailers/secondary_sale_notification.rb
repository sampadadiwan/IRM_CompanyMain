class SecondarySaleNotification < BaseNotification
  # Add your delivery methods
  deliver_by :email, mailer: "SecondarySaleMailer", method: :email_method, format: :email_data

  # Add required params
  param :secondary_sale_id
  param :email_method

  def email_data
    {
      user_id: recipient.id,
      secondary_sale_id: params[:secondary_sale_id]
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @secondary_sale = SecondarySale.find(params[:secondary_sale_id])
    params[:msg] || "SecondarySale: #{@secondary_sale}"
  end

  def url
    secondary_sale_path(id: params[:secondary_sale_id])
  end
end
