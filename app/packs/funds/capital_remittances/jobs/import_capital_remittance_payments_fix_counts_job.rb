class ImportCapitalRemittancePaymentsFixCountsJob < BulkActionJob
  # Capped so the message stays inside user_alerts.message (a 255-char VARCHAR); the full list
  # goes to import_upload.error_text, which the import page renders behind "Show Error".
  MAX_FAILURES_IN_ALERT = 5

  def perform(import_upload_id, capital_remittance_ids)
    Chewy.strategy(:sidekiq) do
      # call the ImportFixCountsJob to roll up the remittance payments
      ImportFixCountsJob.perform_now(import_upload_id)

      import_upload = ImportUpload.find(import_upload_id)

      # ImportCapitalRemittancePayment#verified_requested? already refuses to ask for `verified`
      # on an unapproved call and warns on the row, so the common case never fails here. Anything
      # that still does - a call un-approved between the upload and this job, or any other
      # validation - has to be reported: the results sheet is written and attached by now, so a
      # dropped failure leaves the remittance silently unverified with nothing to explain why.
      failures = []
      fund_ids = Set.new

      # find_each rather than loading every remittance in the import in one go
      CapitalRemittance.where(id: capital_remittance_ids.keys).find_each do |capital_remittance|
        fund_ids << capital_remittance.fund_id
        # We need to reload the capital_remittance, as the capital_remittance_payment counter caches would have updated the capital_remittance
        capital_remittance.verified = capital_remittance_ids[capital_remittance.id.to_s]
        result = CapitalRemittanceUpdate.call(capital_remittance:)
        if result.success?
          send_notification("Saving remittance payment for Folio: #{capital_remittance.folio_id}", import_upload.user_id)
        else
          failures << "Folio #{capital_remittance.folio_id}: #{result[:errors].presence || capital_remittance.errors.full_messages.join(', ')}"
        end
      end

      report_failures(failures, import_upload) if failures.any?

      # Finally run the remittance rollups after all remittances are updated
      # We need to run the counter cache update for the capital_remittances
      # This usually takes a long time.
      CapitalRemittancesCountersJob.perform_now(fund_ids.to_a, import_upload.user_id)

      # Real-time journey progress (no-op without a journey). Worked examples J2.2 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
      CapitalCall.journey_progress_for(CapitalRemittance.where(id: capital_remittance_ids.keys).select(:capital_call_id),
                                       actor: User.find_by(id: import_upload.user_id))
    end
  end

  private

  # Overwrites the status set by ImportUploadJob ("Completed") or by the importer's own
  # unapproved-call warning: a remittance that could not be updated at all is the more urgent
  # fact of the two, and the payments themselves are already imported either way.
  def report_failures(failures, import_upload)
    message = "#{failures.size} remittance(s) could not be updated after importing payments: " \
              "#{failures.first(MAX_FAILURES_IN_ALERT).join('; ')}"
    import_upload.update(status: message, error_text: failures.join("\n"))
    UserAlert.create!(user_id: import_upload.user_id, entity_id: import_upload.entity_id,
                      level: "danger", message: message.truncate(255))
  end
end
