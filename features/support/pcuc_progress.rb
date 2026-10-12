# Progress feed for the `cuc` / `pcuc` scripts in bin/ and for `bin/pcuc-status`.
#
# Each cucumber process appends one line per finished scenario (`passed` / `failed`) to a file
# of its own; the readers sum those files against a dry-run scenario count to print
# "412/1530 scenarios (27%) · 3 failed". Where the files go:
#   1. $PCUC_PROGRESS_DIR - set by cuc/pcuc, which own and later remove the directory.
#   2. Otherwise, for a parallel_tests worker (PARALLEL_TEST_GROUPS is set), the fallback
#      tmp/pcuc_progress/<parallel_cucumber pid>. Every worker's parent is the
#      parallel_cucumber process, so `pcuc-status` finds the run's feed from that pid alone -
#      a run started without pcuc (plain `bundle exec parallel_cucumber`, another session, a
#      stale shell) still reports live failures. pcuc-status removes these once the pid is gone.
# A single-process cucumber started without cuc, and anything on CI, writes nothing.
PCUC_FALLBACK_FEED = ENV['PARALLEL_TEST_GROUPS'].present? && ENV['CI'].blank?
PCUC_PROGRESS_DIR = ENV['PCUC_PROGRESS_DIR'].presence ||
                    (File.expand_path("tmp/pcuc_progress/#{Process.ppid}") if PCUC_FALLBACK_FEED)

if PCUC_PROGRESS_DIR
  # The fallback dir is ours to create; every worker of the run races to it, which mkdir_p allows.
  begin
    FileUtils.mkdir_p(PCUC_PROGRESS_DIR)
  rescue SystemCallError
    nil # progress is cosmetic: an unwritable tmp/ must not stop the suite booting
  end

  # One file per worker (TEST_ENV_NUMBER 1..N), so concurrent workers never write the same file
  # and no locking is needed. worker_N gets a line per finished scenario; current_N holds the
  # scenario running now (pcuc-status shows it, and flags one running for minutes). Not named
  # worker_N.current: every reader globs worker_* and would count it as finished scenarios.
  PCUC_PROGRESS_FILE = File.join(PCUC_PROGRESS_DIR, "worker_#{ENV.fetch('TEST_ENV_NUMBER', '0')}")
  PCUC_CURRENT_FILE = File.join(PCUC_PROGRESS_DIR, "current_#{ENV.fetch('TEST_ENV_NUMBER', '0')}")

  # Tab-separated "<location>\t<name>\t<epoch>": readers split on tabs, so squash any whitespace
  # run (tabs, newlines from a multi-line outline name) in the name to one space.
  # A lambda, not a top-level def, so it does not become a method on every object in the suite.
  PCUC_PROGRESS_FIELDS = lambda do |scenario|
    "#{scenario.location}\t#{scenario.name.gsub(/\s+/, ' ')}\t#{Time.now.to_i}"
  end

  Before do |scenario|
    # Overwritten, not appended: only the scenario running now matters.
    File.write(PCUC_CURRENT_FILE, PCUC_PROGRESS_FIELDS.call(scenario))
  rescue SystemCallError
    nil # progress is cosmetic, never fail a scenario on it
  end

  After do |scenario|
    # Open-append-close per scenario: the line is on disk the moment the ticker next reads it,
    # and a crash mid-run loses nothing already counted. The status word comes first, so a reader
    # that only counts lines or `^failed` needs nothing else; the epoch orders failures across
    # workers ("last fail").
    File.open(PCUC_PROGRESS_FILE, 'a') do |f|
      f.puts("#{scenario.failed? ? 'failed' : 'passed'}\t#{PCUC_PROGRESS_FIELDS.call(scenario)}")
    end
    # Nothing is running until the next Before: a worker that has just finished its last
    # scenario must not keep showing it as current.
    FileUtils.rm_f(PCUC_CURRENT_FILE)
  rescue SystemCallError
    nil # pcuc removed the directory (run interrupted): progress is cosmetic, never fail a scenario on it.
  end
end
