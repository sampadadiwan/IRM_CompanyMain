# The only way a Document Checks run is created. Locks the record row so two clicks can't start two runs,
# expires runs nobody will finish, then queues the run (or leaves it for the caller to perform now, as the
# bulk job does to keep its pacing).
#
#   DocChecks::StartRun.call(record:, user:, trigger: "manual")             # => DocCheckRun (queued)
#   DocChecks::StartRun.call(record:, user:, trial: true)                   # Try on a KYC
#   raises DocChecks::Error::AlreadyRunning when a non-trial run is queued or running
#
# See openspec/changes/document-checks/design.md (card ④ Run). Worked example E14.
module DocChecks
  class StartRun
    def self.call(record:, user:, trigger: "manual", trial: false, enqueue: true)
      run = nil
      record.with_lock do
        # Trials neither block nor are blocked: they change nothing
        guard_active!(record) unless trial
        run = DocCheckRun.create!(entity_id: record.entity_id, record:, user:, trial:,
                                  trigger: trial ? "trial" : trigger, status: "queued")
      end
      # Enqueue after the lock's transaction commits, so the job always finds the run
      RunJob.perform_later(run.id) if enqueue
      run
    end

    def self.guard_active!(record)
      # A run nobody will finish (the worker died) doesn't block a new one. Decide which runs are stale
      # before expiring them — an expired run is no longer active, so asking afterwards would misjudge it.
      stale, live = DocCheckRun.real.active.for_record(record).to_a.partition(&:expired?)
      stale.each(&:expire!)
      return if live.empty?

      raise Error::AlreadyRunning, I18n.t("doc_checks.run.already_running", record: record.to_s)
    end
    private_class_method :guard_active!
  end
end
