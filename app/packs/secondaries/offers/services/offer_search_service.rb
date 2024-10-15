class OfferSearchService
  def fetch_rows(offers, params)
    offers = offers.where(approved: true) if params[:approved].present? && params[:approved] == "true"
    offers = offers.where(approved: false) if params[:approved].present? && params[:approved] == "false"

    offers = offers.where(verified: true) if params[:verified].present? && params[:verified] == "true"
    offers = offers.where(verified: false) if params[:verified].present? && params[:verified] == "false"

    offers = offers.where(final_agreement: true) if params[:final_agreement].present? && params[:final_agreement] == "true"
    offers = offers.where(final_agreement: false) if params[:final_agreement].present? && params[:final_agreement] == "false"

    offers = offers.where.not(interest_id: nil) if params[:matched].present? && params[:matched] == "true"
    offers = offers.where(interest_id: nil) if params[:matched].present? && params[:matched] == "false"

    offers = offers.where(secondary_sale_id: params[:secondary_sale_id]) if params[:secondary_sale_id].present?
    offers = offers.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id].present?

    offers.joins(:investor, :user).includes(:secondary_sale, :entity, holding: :funding_round)
  end
end
