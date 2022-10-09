class ImportUpload < ApplicationRecord
  SAMPLES = { "IA_SAMPLE" => "/sample_uploads/investor_access.xlsx",
              "INVESTORS_SAMPLE" => "/sample_uploads/investors.xlsx",
              "HOLDINGS_SAMPLE" => "/sample_uploads/holdings.xlsx" }.freeze

  belongs_to :entity
  belongs_to :owner, polymorphic: true
  belongs_to :user

  has_one_attached :import_file, service: :amazon
  has_one_attached :import_results, service: :amazon

  validates :import_file,
            attached: true,
            content_type: ['application/xls', 'application/xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'],
            size: { less_than: 5.megabytes, message: 'must be less than 5MB in size' }

  after_create :run_import_job
  def run_import_job
    ImportUploadJob.set(wait_until: 2.seconds).perform_later(id) unless Rails.env.test?
  end

  def percent_completed
    return 0 if total_rows_count.zero?

    (processed_row_count.to_f / total_rows_count * 100).round(2)
  end
end
