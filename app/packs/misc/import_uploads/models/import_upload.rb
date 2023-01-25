class ImportUpload < ApplicationRecord
  SAMPLES = { "IA_SAMPLE" => "/sample_uploads/investor_access.xlsx",
              "INVESTORS_SAMPLE" => "/sample_uploads/investors.xlsx",
              "FUND_INVESTORS_SAMPLE" => "/sample_uploads/fund_investors.xlsx",
              "HOLDINGS_SAMPLE" => "/sample_uploads/holdings.xlsx",
              "OFFERS_SAMPLE" => "/sample_uploads/offers.xlsx",
              "CAPITAL_CALL_SAMPLE" => "/sample_uploads/capital_calls.xlsx",
              "CAPITAL_REMITTANCE_SAMPLE" => "/sample_uploads/capital_remittances.xlsx",
              "CAPITAL_REMITTANCE_PAYMENT_SAMPLE" => "/sample_uploads/capital_remittance_payments.xlsx",
              "CAPITAL_DISTRIBUTION_SAMPLE" => "/sample_uploads/capital_distributions.xlsx",
              "INVESTOR_KYCS_SAMPLE" => "/sample_uploads/investor_kycs.xlsx",
              "CAPITAL_DISTRIBUTION_PAYMENT_SAMPLE" => "/sample_uploads/capital_distribution_payments.xlsx",
              "CAPITAL_COMMITMENT_SAMPLE" => "/sample_uploads/capital_commitments.xlsx",
              "FUND_DOCS_SAMPLE" => "/sample_uploads/commitment_docs.zip" }.freeze

  belongs_to :entity
  belongs_to :owner, polymorphic: true
  belongs_to :user

  include FileUploader::Attachment(:import_file)
  include FileUploader::Attachment(:import_results)

  after_create_commit :run_import_job
  def run_import_job
    ImportUploadJob.set(wait_until: 2.seconds).perform_later(id) unless Rails.env.test?
  end

  after_save_commit :broadcast_iu, on: [:update]

  def broadcast_iu
    broadcast_update partial: "/import_uploads/show"
  end

  def percent_completed
    return 0 if total_rows_count.zero?

    (processed_row_count.to_f / total_rows_count * 100).round(2)
  end
end
