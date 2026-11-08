# frozen_string_literal: true

module Dr
  # Classifies the Pulumi stack lock before a DR drill starts (openspec fix-dr-drill-hygiene).
  #
  # Pulumi writes a lock file while an update runs; a second `pulumi up` on the same stack refuses
  # with "the stack is currently locked". aws:dr_drill used to discover that only at `pulumi up`,
  # and its ensure block then logged the refusal as a FAILED drill ("0.1 minutes") - three such
  # rows on 2026-11-08 were collisions, not drills. Checking first lets the drill refuse cleanly,
  # with no drill row, and tell the operator who holds the lock.
  #
  # Pure: callers fetch the lock files from the S3 backend and say whether a pid is alive.
  # Never cancels a lock - that is the operator's decision, given the exact command.
  module PulumiLock
    # One lock file's content, as the S3 backend stores it
    Lock = Data.define(:pid, :username, :hostname, :timestamp)
    # state: :free, :running_here, :stale, :held_elsewhere. Only :free may proceed.
    Result = Data.define(:state, :message)

    module_function

    # The backend the Pulumi CLI is logged into, from ~/.pulumi/credentials.json ("current"): a local
    # read, no network. Used when `pulumi whoami` cannot answer - it reads the CURRENT backend with
    # the keys in the environment, so after staging drills (logged into the staging state bucket)
    # with production keys loaded it fails with a cross-account 403, and the backend preflight
    # gave up instead of switching (production readiness, 2026-11-08). nil if unknown.
    def backend_from_credentials(json)
      current = JSON.parse(json.to_s)["current"].to_s.strip
      current.empty? ? nil : current
    rescue JSON::ParserError
      nil
    end

    # Parses a lock file's JSON. Pulumi writes lowercase keys; accept either case to be safe.
    def parse(json)
      data = JSON.parse(json).transform_keys(&:downcase)
      Lock.new(pid: data["pid"].to_i, username: data["username"].to_s, hostname: data["hostname"].to_s,
               timestamp: parse_time(data["timestamp"]))
    end

    # locks: lock file contents (JSON strings) for this stack; alive: ->(pid) { true/false }
    def classify(locks, stack:, local_host:, alive:)
      # H1 — nobody holds the stack
      return Result.new(:free, "Pulumi lock: free") if locks.empty?

      lock = locks.map { |json| parse(json) }.min_by { |l| l.timestamp || Time.now.utc }
      who = "#{lock.username}@#{lock.hostname} (pid #{lock.pid}) since #{lock.timestamp&.utc&.iso8601} (#{age(lock.timestamp)} ago)"
      cancel = "cd ../IRM-Infra && pulumi cancel --stack #{stack} --yes"

      if lock.hostname == local_host
        # X1 — another run is genuinely in progress here: wait for it
        return Result.new(:running_here, "#{stack}: a DR run is already running on this machine — #{who}. Wait for it to finish.") if alive.call(lock.pid)

        # E2 — the process that took the lock is gone (killed run, closed terminal)
        return Result.new(:stale, "#{stack}: stale lock from a run that no longer exists — #{who}. " \
                                  "If no run is in progress, clear it with: #{cancel}")
      end

      # E3 — another machine's run: name it, so the operator knows whom to ask
      Result.new(:held_elsewhere, "#{stack}: locked by #{who}. Wait, or ask them; if that run is dead: #{cancel}")
    end

    # Plain Time, not Time.zone: aws:dr_drill runs without the Rails environment, where
    # Time.zone is nil (dr_requires.rb). nil for a missing or unreadable timestamp.
    def parse_time(value)
      Time.parse(value.to_s).utc
    rescue ArgumentError
      nil
    end

    # "5 min" / "2 h 10 min" - enough to judge whether a lock is plausibly still live
    def age(timestamp)
      return "unknown time" unless timestamp

      minutes = ((Time.now.utc - timestamp) / 60).floor
      minutes < 60 ? "#{minutes} min" : "#{minutes / 60} h #{minutes % 60} min"
    end
  end
end
