# Patch InlineAdapter so set(wait: ...).perform_later works in test without raising
# NotImplementedError — the wait is silently ignored and the job runs inline.
ActiveJob::QueueAdapters::InlineAdapter.prepend(Module.new do
  def enqueue_at(job, _timestamp)
    enqueue(job) # ignore the scheduled timestamp, run immediately
  end
end)

# Every scenario starts on the configured adapter (:inline, config/environments/test.rb). Steps that
# switch ActiveJob::Base to :test to inspect enqueued jobs (kpi_autofill_on_approval_steps.rb) never
# switched back, so every later scenario in the same process silently queued its deliver_later
# emails and perform_later imports instead of running them — failures that appeared only when
# parallel_tests grouped those features into one worker, and passed whenever the file ran alone.
After do
  ActiveJob::Base.queue_adapter = :inline unless ActiveJob::Base.queue_adapter.is_a?(ActiveJob::QueueAdapters::InlineAdapter)
end
