class ImportCapitalRemittancesFixCountsJob < BulkActionJob
  def perform(import_upload_id)
    Chewy.strategy(:sidekiq) do
      # call the default ImportFixCountsJob first
      ImportFixCountsJob.perform_now(import_upload_id)
      import_upload = ImportUpload.find(import_upload_id)
      # We need to run the counter cache update for the capital_remittances
      # This usually takes a long time.
      fund_ids = CapitalRemittance.where(import_upload_id: import_upload.id).pluck(:fund_id).uniq
      CapitalRemittancesCountersJob.perform_now(fund_ids, import_upload.user_id)
    end
  end
end
