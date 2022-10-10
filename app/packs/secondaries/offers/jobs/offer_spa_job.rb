# Unused
# TODO delete later
class OfferSpaJob < ApplicationJob
  queue_as :default

  # For a secondary sale, sometimes we generate the SPAs offile using mail merge
  # These are then uploaded to a specifc bucket in S3
  # We then run this job
  def perform(secondary_sale_id, bucket, prefix)
    s3_client = Aws::S3::Client.new
    resp = s3_client.list_objects_v2({ bucket:, prefix: })

    resp.contents.each do |obj|
      offer = get_offer(obj, secondary_sale_id)
      if offer
        begin
          download(obj, s3_client, bucket)
          new_document(obj, offer)
        ensure
          cleanup(obj)
        end
      else
        Rails.logger.info "Offer not found for #{obj.key}"
      end
    rescue StandardError => e
      Rails.logger.error "Error: #{e.message}"
    end
  end

  def get_offer(obj, secondary_sale_id)
    # Get the offer based on the file name
    offer_id = obj.key.split("_")[1].to_i
    Rails.logger.info "Finding Offer with id #{offer_id}"
    Offer.where(secondary_sale_id:, id: offer_id).first
  end

  def download(obj, s3_client, bucket)
    s3_client.get_object(
      response_target: "tmp/#{obj.key}",
      bucket:,
      key: obj.key
    )
    Rails.logger.info "Downloaded file tmp/#{obj.key}"
  end

  def new_document(obj, offer)
    Document.create!(name: obj.key, orignal: true, owner: offer,
                     user_id: offer.user_id,
                     file: File.open("tmp/#{obj.key}", binmode: true))

    Rails.logger.info "Attached tmp/#{obj.key} to Offer #{offer.id}"
  end

  def cleanup(obj)
    Rails.logger.info "Cleanup file tmp/#{obj.key}"
    FileUtils.rm_rf("tmp/#{obj.key}", secure: true)
  end
end
