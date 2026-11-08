# frozen_string_literal: true

# Rebuilds the search indexes in the background after a disaster recovery
# (openspec fix-dr-search-index-after-restore, decision 2026-11-08: "enqueue and move on").
#
# Elasticsearch is not backed up, so a recovered environment starts with empty indexes. The DR
# queues this job while the site is still in maintenance (cap recovery:reindex_search_later); it
# runs once Sidekiq starts with traffic back on, so users get the site at once and search fills in.
# Its progress is recorded in Rails.cache (Dr::SearchIndexes::STATUS_KEY) - dr:verify and the DR
# report read it. An incomplete index is a warning, never a failure.
#
# The blocking, hands-on equivalent for operators stays: bundle exec cap <stage> recovery:reindex_search
class SearchReindexJob < ApplicationJob
  # The dedicated Elasticsearch queue (config/initializers/sidekiq.rb)
  queue_as :chewy

  # only: index class names to rebuild, or empty for every index the DR owns
  def perform(only = [])
    indexes = Dr::SearchIndexes.select(only)
    # Keep the queued record (its queued_at) and mark it running
    status = (Dr::SearchIndexes.read_status || {}).merge(
      state: "running", started_at: Time.now.utc.iso8601, total: indexes.size, done: 0, problems: []
    )
    Dr::SearchIndexes.write_status(status)

    # exact: false - traffic is on while this runs, so a few records may be in flight
    Dr::SearchIndexes.rebuild!(indexes, exact: false, on_progress: lambda { |done, (_, grade, _)|
      status[:done] = done
      status[:problems] << grade.detail unless grade.status == :ok
      Dr::SearchIndexes.write_status(status)
    })

    Dr::SearchIndexes.write_status(status.merge(state: "finished", finished_at: Time.now.utc.iso8601))
  end
end
