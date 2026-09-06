# Replaces DatabaseCleaner's per-scenario TRUNCATE-across-~160-tables with a
# whole-file restore from a pristine per-worker snapshot, taken once right
# after schema load. Uses SQLite's Backup API (a page-level copy performed
# through a live connection) rather than `cp`-ing the file on disk — a raw
# file copy would leave any other open connection to the same file (e.g. the
# Playwright server thread's pooled connection) holding a stale fd/cached
# pages. The Backup API writes through SQLite's normal locking/change-counter
# machinery, so other connections see the restored state correctly on their
# next read, same as if another process had written the file.
#
# Because this resets the whole file rather than relying on a shared
# transaction, it's correct regardless of which Capybara driver a scenario
# uses (single-connection rack_test or a Playwright-driven scenario with a
# separate server-thread connection) — it doesn't need the @javascript-tag
# split TruncationStrategy relies on.
require "sqlite3"

class SqliteSnapshotStrategy < Cucumber::Rails::Database::Strategy
  class << self
    def live_db_path
      ActiveRecord::Base.connection.raw_connection.filename("main")
    end

    def template_path
      "#{live_db_path}.template"
    end

    # Runs once per worker process, on the first scenario's before hook —
    # at that point nothing has run yet, so the live db is still the
    # freshly-migrated, empty state. Built via the Backup API (not `cp`)
    # so a mid-write/WAL-checkpoint file state can't produce a torn copy.
    #
    # Deliberately memoized in-process (@template_ready), not by checking
    # whether the file already exists on disk: a TEST_ENV_NUMBER's template
    # file can outlive the worker process that wrote it (an interrupted run,
    # a failed cleanup). A fresh process must always (re)build its own
    # template rather than silently trusting a leftover file that may
    # reflect a stale schema from a previous run.
    def ensure_template!
      return if @template_ready

      path = template_path
      src = ActiveRecord::Base.connection.raw_connection
      dst = SQLite3::Database.new(path)
      begin
        backup = SQLite3::Backup.new(dst, "main", src, "main")
        backup.step(-1)
        backup.finish
      ensure
        dst.close
      end
      Rails.logger.info("[SqliteSnapshotStrategy] snapshot taken -> #{path}")
      @template_ready = true
    end

    def cleanup!
      return unless @template_ready

      # SQLite may leave -wal/-shm journals next to the template; deleting only
      # the main file orphans them for the next worker that reuses this
      # TEST_ENV_NUMBER, which would then open a fresh template alongside a
      # stale WAL journal from a now-deleted database.
      Dir.glob("#{template_path}*").each { |f| File.delete(f) }
    end
  end

  # The primary reset happens in `after`, not `before` — see the note there for
  # why. `before_js`/`before_non_js` also restore (in addition to
  # ensure_template!) purely as a backstop: if a previous scenario's `after`
  # never ran (a hook exception aborting before `after`, or the process getting
  # killed mid-scenario — this DB setup has hit stale-state issues from crashed
  # runs before), the next scenario would otherwise inherit whatever dirty
  # state was left behind with nothing to catch it. The extra restore is cheap
  # (a page-level copy of a RAM-backed file), so paying it on both ends of a
  # scenario is worth the robustness.
  def before_js
    restore!
  end

  def before_non_js
    restore!
  end

  def after
    restore!
  end

  private

  def restore!
    self.class.ensure_template!

    dst = ActiveRecord::Base.connection.raw_connection
    src = SQLite3::Database.new(self.class.template_path, readonly: true)
    begin
      backup = SQLite3::Backup.new(dst, "main", src, "main")
      backup.step(-1)
      backup.finish
    ensure
      src.close
    end
    Rails.logger.info("[SqliteSnapshotStrategy] restored from snapshot <- #{self.class.template_path}")
  end
end

Cucumber::Rails::Database.javascript_strategy = SqliteSnapshotStrategy

# env.rb's `DatabaseCleaner[:active_record].strategy = :truncation` is driven by
# database_cleaner-core's own Before/After hooks, which fire independently of
# Cucumber::Rails::Database.javascript_strategy above. Left alone, that truncation
# would still run on every scenario in addition to the restore — the exact cost
# this strategy exists to remove. Swap it for a no-op so the restore is the only
# cleanup that happens. (The 41-table exclusion list on that truncation config in
# env.rb is now dead code, kept only as a harmless fallback.)
DatabaseCleaner[:active_record].strategy = DatabaseCleaner::NullStrategy.new

AfterAll do
  SqliteSnapshotStrategy.cleanup!
end
