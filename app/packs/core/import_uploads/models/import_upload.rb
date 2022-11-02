class ImportUpload < ApplicationRecord
  SAMPLES = { "IA_SAMPLE" => "/sample_uploads/investor_access.xlsx",
              "INVESTORS_SAMPLE" => "/sample_uploads/investors.xlsx",
              "HOLDINGS_SAMPLE" => "/sample_uploads/holdings.xlsx",
              "OFFERS_SAMPLE" => "/sample_uploads/offers.xlsx" }.freeze

  belongs_to :entity
  belongs_to :owner, polymorphic: true
  belongs_to :user

  include FileUploader::Attachment(:import_file)
  include FileUploader::Attachment(:import_results)

  after_create :run_import_job
  def run_import_job
    ImportUploadJob.set(wait_until: 2.seconds).perform_later(id) unless Rails.env.test?
  end

  def percent_completed
    return 0 if total_rows_count.zero?

    (processed_row_count.to_f / total_rows_count * 100).round(2)
  end
end
