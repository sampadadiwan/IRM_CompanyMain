class OfferSpaSignatureJob < ApplicationJob
  queue_as :default

  def perform(secondary_sale_id, offer_id)
    Chewy.strategy(:sidekiq) do
      if offer_id
        # We have an offer id, so generate the adhaar esign link and send to digio
        perform_offer(offer_id)
      else
        # For all the offers of this sale generate_spa_signatures in the background
        perform_sale(secondary_sale_id)
      end
    end
  end

  def perform_offer(offer_id)
    offer = Offer.find(offer_id)
    if offer.seller_signature_types.include?("adhaar") || offer.interest&.buyer_signature_types&.include?("adhaar")
      offer_esign_provider = OfferEsignProvider.new(offer)
      offer_esign_provider.generate_spa_signatures
    else
      Rails.logger.debug { "OfferSpaSignatureJob: Doing nothing as adhaar is not set for either seller_signature_types or buyer_signature_types of the offer #{offer_id}" }
    end
  end

  def perform_sale(secondary_sale_id)
    # For all the offers of this sale generate_spa_signatures in the background
    secondary_sale = SecondarySale.find(secondary_sale_id)
    if secondary_sale.seller_signature_types.include?("adhaar") || secondary_sale.buyer_signature_types.include?("adhaar")
      secondary_sale.offers.includes(:user).verified.not_final_agreement.each do |o|
        OfferSpaSignatureJob.perform_later(secondary_sale_id, o.id)
      end
    else
      Rails.logger.debug { "OfferSpaSignatureJob: Doing nothing as adhaar is not set for either seller_signature_types or buyer_signature_types of the sale #{secondary_sale_id}" }
    end
  end
end
