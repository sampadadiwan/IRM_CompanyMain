class OfferSpaSignatureJob < ApplicationJob
  queue_as :default

  def perform(secondary_sale_id, offer_id)
    secondary_sale = SecondarySale.find(secondary_sale_id)
    if secondary_sale.seller_signature_types.set?(:adhaar) || secondary_sale.buyer_signature_types.set?(:adhaar)
      Chewy.strategy(:sidekiq) do
        if offer_id
          offer = Offer.find(offer_id)
          offer.generate_spa_signatures
        else
          # For all the offers of this sale generate_spa_signatures
          secondary_sale.offers.includes(:user).verified.not_final_agreement.each(&:generate_spa_signatures_delayed)
        end
      end
    else
      Rails.logger.debug { "OfferSpaSignatureJob: Doing nothing as adhaar is not set for either seller_signature_types or buyer_signature_types of the sale #{secondary_sale_id}" }
    end
  end
end
