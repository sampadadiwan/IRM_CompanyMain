class OfferSpaJob < ApplicationJob
  queue_as :default

  def perform(secondary_sale_id)
    @secondary_sale = SecondarySale.find(secondary_sale_id)
    @secondary_sale.offers.approved.each(&:generate_spa_pdf)
  end
end
