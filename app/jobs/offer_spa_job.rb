class OfferSpaJob < ApplicationJob
  queue_as :default

  def perform(bucket_name, prefix)
    # client = Aws::S3::Client.new
    # resp = client.list_objects_v2({
    #                                 bucket: bucket_name, # required
    #                                 prefix:
    #                               })

    # @secondary_sale = SecondarySale.find(secondary_sale_id)
    # @secondary_sale.offers.approved.each(&:generate_spa_pdf)
  end
end
