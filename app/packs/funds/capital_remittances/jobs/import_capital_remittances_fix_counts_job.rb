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

      # Real-time journey progress (no-op without a journey). Worked examples J2.2 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
      CapitalCall.journey_progress_for(CapitalRemittance.where(import_upload_id: import_upload.id).select(:capital_call_id),
                                       actor: User.find_by(id: import_upload.user_id))
    end
  end
end
