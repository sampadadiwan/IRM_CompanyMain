# Patch InlineAdapter so set(wait: ...).perform_later works in test without raising
# NotImplementedError — the wait is silently ignored and the job runs inline.
ActiveJob::QueueAdapters::InlineAdapter.prepend(Module.new do
  def enqueue_at(job, _timestamp)
    enqueue(job) # ignore the scheduled timestamp, run immediately
  end
end)
