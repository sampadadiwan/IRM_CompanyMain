class OfferSearchService
  def self.perform(offers, current_user, params)
    offers = offers.where(id: search_ids(params, current_user)) if params[:search] && params[:search][:value].present?
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

    offers.joins(:investor, :user).includes(:secondary_sale, :entity)
  end

  def self.search_ids(params, current_user)
    # This is only when the datatable sends a search query
    query = "#{params[:search][:value]}*"
    entity_ids = [current_user.entity_id]
    OfferIndex.filter(terms: { entity_id: entity_ids })
              .query(query_string: { fields: OfferIndex::SEARCH_FIELDS,
                                     query:, default_operator: 'and' }).per(100).map(&:id)
  end
end
