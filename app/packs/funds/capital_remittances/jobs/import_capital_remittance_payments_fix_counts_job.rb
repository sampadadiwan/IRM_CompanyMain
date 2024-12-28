class ImportCapitalRemittancePaymentsFixCountsJob < BulkActionJob
  def perform(import_upload_id, capital_remittance_ids)
    Chewy.strategy(:sidekiq) do
      # call the ImportFixCountsJob to roll up the remittance payments
      ImportFixCountsJob.perform_now(import_upload_id)

      import_upload = ImportUpload.find(import_upload_id)

      capital_remittances = CapitalRemittance.where(id: capital_remittance_ids.keys)
      capital_remittances.each do |capital_remittance|
        # We need to reload the capital_remittance, as the capital_remittance_payment counter caches would have updated the capital_remittance
        capital_remittance.verified = capital_remittance_ids[capital_remittance.id.to_s]
        CapitalRemittanceUpdate.call(capital_remittance:)
        send_notification("Saving remittance payment for Folio: #{capital_remittance.folio_id}", import_upload.user_id)
      end
      # Finally run the remittance rollups after all remittances are updated
      # We need to run the counter cache update for the capital_remittances
      # This usually takes a long time.
      fund_ids = capital_remittances.pluck(:fund_id).uniq
      CapitalRemittancesCountersJob.perform_now(fund_ids, import_upload.user_id)
    end
  end
end
