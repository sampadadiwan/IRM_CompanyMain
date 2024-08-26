class OfferSpaJob < DocGenJob
  def templates(model = nil)
    if @template_id.present?
      [Document.find(@template_id)]
    elsif model && model.custom_fields.docs_to_generate.present?
      # In special cases there is a custom field in the offer, docs_to_generate, that specifies which documents to generate. This is to enable some offers to have only one doc generated, but others to have more than one doc. E.x if the shares are in DEMAT, then only SPA needs to be generated, if not then SPA and another doc needs to be generated.
      Rails.logger.debug { "OfferSpaJob: Generating only docs_to_generate #{template_names}" }
      template_names = model.custom_fields.docs_to_generate.split(",").map(&:strip)
      model.secondary_sale.documents.where(owner_tag: "Offer Template").where(name: template_names)
    else
      Rails.logger.debug "OfferSpaJob: Generating all Offer Templates"
      @secondary_sale.documents.where(owner_tag: "Offer Template")
    end
  end

  def models
    if @offer_id.present?
      [Offer.find(@offer_id)]
    else
      @secondary_sale.offers.verified
    end
  end

  def validate(offer)
    return false, "No Offer found" if offer.blank?
    return false, "Offer not approved" unless offer.approved

    [true, ""]
  end

  def generator
    OfferSpaGenerator
  end

  def cleanup_previous_docs(model, template)
    model.documents.not_templates.where(name: template.name).find_each(&:destroy)
  end

  def perform(secondary_sale_id, offer_id, user_id, template_id: nil)
    @secondary_sale_id = secondary_sale_id
    @secondary_sale = SecondarySale.find(@secondary_sale_id)

    @offer_id = offer_id
    @user_id = user_id
    @template_id = template_id

    @start_date = Time.zone.now
    @end_date = Time.zone.now

    Chewy.strategy(:sidekiq) do
      generate(@start_date, @end_date, @user_id) if valid_inputs
    end

    @error_msg
  end
end
