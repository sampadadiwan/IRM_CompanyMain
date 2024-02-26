class OfferSearchService
  def fetch_rows(offers, params)
    offers = offers.where(approved: true) if params[:approved].present? && params[:approved] == "true"
    offers = offers.where(approved: false) if params[:approved].present? && params[:approved] == "false"
    offers = offers.where(verified: true) if params[:verified].present? && params[:verified] == "true"
    offers = offers.where(verified: false) if params[:verified].present? && params[:verified] == "false"
    offers = offers.where(secondary_sale_id: params[:secondary_sale_id]) if params[:secondary_sale_id].present?
    offers = offers.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id].present?
    offers.joins(:investor, :user).includes(:secondary_sale, :entity, :interest, holding: :funding_round)
  end
end
