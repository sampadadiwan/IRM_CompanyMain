class OfferNotification < BaseNotification
  # Add your delivery methods
  deliver_by :email, mailer: "OfferMailer", method: :email_method, format: :email_data

  # Add required params
  param :offer_id
  param :email_method

  def email_method
    params[:email_method]
  end

  def email_data
    {
      user_id: recipient.id,
      offer_id: params[:offer_id]
    }
  end

  # Define helper methods to make rendering easier.
  def message
    @offer = Offer.find(params[:offer_id])
    params[:msg] || "Offer: #{@offer}"
  end

  def url
    offer_path(id: params[:offer_id])
  end
end
