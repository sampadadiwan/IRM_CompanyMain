# Runs after a distribution payments import (ImportUtil#post_process finds it by name): the default
# counter fix, then a journey re-check of every distribution the import added payments to, so an
# Upload distribution's Create payments task passes (or reports a failed upload) at once.
# No-op for distributions without a journey.
# Worked examples E4 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
class ImportCapitalDistributionPaymentsFixCountsJob < ApplicationJob
  # Same queue as ImportFixCountsJob: counter fixes run serially to avoid deadlocks
  queue_as :serial
  sidekiq_options retry: 0

  def perform(import_upload_id)
    # The default ImportFixCountsJob first, as for every import
    ImportFixCountsJob.perform_now(import_upload_id)
    import_upload = ImportUpload.find(import_upload_id)

    distribution_ids = CapitalDistributionPayment.where(import_upload_id: import_upload.id).select(:capital_distribution_id)
    CapitalDistribution.journey_progress_for(distribution_ids, actor: User.find_by(id: import_upload.user_id))
  end
end
