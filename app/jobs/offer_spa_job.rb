class OfferSpaJob < ApplicationJob
  queue_as :default

  # For a secondary sale, sometimes we generate the SPAs offile using mail merge
  # These are then uploaded to a specifc bucket in S3
  # We then run this job
  def perform(secondary_sale_id, bucket, prefix)
    client = Aws::S3::Client.new
    resp = client.list_objects_v2({ bucket:, prefix: })

    resp.contents.each do |obj|
      # Get the offer based on the file name
      offer_id = obj.key.split(".").first.to_i
      Rails.logger.info "Finding Offer with id #{offer_id}"
      offer = Offer.where(secondary_sale_id:, id: offer_id).first

      if offer
        attach_blob(offer, obj)
      else
        Rails.logger.info "Offer not found for #{obj.key}"
      end
    rescue StandardError => e
      Rails.logger.error "Error: #{e.message}"
    end
  end

  def attach_blob(offer, obj)
    # Create an ActiveStorage Blob
    blob = ActiveStorage::Blob.create_before_direct_upload!(filename: obj.key,
                                                            byte_size: obj.size,
                                                            checksum: obj.etag.delete('"'),
                                                            content_type: "application/pdf")
    blob.update_attribute(:key, obj.key)

    # Attach the blob to the offer
    offer.spa = blob.signed_id
    offer.save

    Rails.logger.info "#{obj.key} is now attached to Offer #{offer.id}"
  end
end
