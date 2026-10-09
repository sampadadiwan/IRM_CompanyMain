# Progress feed for the `cuc` / `pcuc` shell functions in ~/.zshrc.
#
# They set PCUC_PROGRESS_DIR before launching cucumber (or parallel_cucumber, whose workers
# inherit it); each process appends one line per finished scenario to a file of its own. The
# functions' ticker sums those files against a dry-run scenario count to print
# "412/1530 scenarios (27%)". A run started any other way (bundle exec cucumber, CI) never sets
# the variable, so this hook does nothing there.
PCUC_PROGRESS_DIR = ENV['PCUC_PROGRESS_DIR'].presence

if PCUC_PROGRESS_DIR
  # One file per worker (TEST_ENV_NUMBER 1..N), so concurrent workers never write the same file
  # and no locking is needed.
  PCUC_PROGRESS_FILE = File.join(PCUC_PROGRESS_DIR, "worker_#{ENV.fetch('TEST_ENV_NUMBER', '0')}")

  After do |scenario|
    # Open-append-close per scenario: the line is on disk the moment the ticker next reads it,
    # and a crash mid-run loses nothing already counted.
    File.open(PCUC_PROGRESS_FILE, 'a') { |f| f.puts(scenario.failed? ? 'failed' : 'passed') }
  rescue SystemCallError
    nil # pcuc removed the directory (run interrupted): progress is cosmetic, never fail a scenario on it.
  end
end
