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

    # Runs once per worker process, on the first scenario's before hook.
    # The live db is emptied first (empty_live_db!) so the snapshot is the
    # freshly-migrated state even if the file was reused dirty. Built via the Backup API (not `cp`)
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
      # The live db is NOT guaranteed empty: pcuc reuses /dev/shm/test_N.sqlite3 whenever the file
      # exists, so rows left by an interrupted run (or written after the last restore) would be baked
      # into the template and restored into every scenario, with ids no longer starting at 1.
      empty_live_db!(src)
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

    # Tables that hold schema state, not test data: emptying them would make Rails think the
    # db is unmigrated.
    KEEP_TABLES = %w[schema_migrations ar_internal_metadata].freeze

    # Deletes every row from every data table and resets the AUTOINCREMENT counters, so the
    # template is the freshly-migrated state whatever the file held before. Logs what it removed
    # so a dirty worker db is visible in log/test_N.log rather than silent.
    def empty_live_db!(db)
      # Rails' raw connection returns rows as hashes (results_as_hash), a bare SQLite3::Database as arrays
      tables = db.execute("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
                 .map { |row| row.is_a?(Hash) ? row["name"] : row.first } - KEEP_TABLES
      # Count first, only to report the leftovers
      leftovers = tables.index_with { |t| db.get_first_value("SELECT COUNT(*) FROM \"#{t}\"") }.select { |_, n| n.positive? }
      # A db can hold no rows yet still have advanced id counters (rows inserted, then deleted)
      counters = db.get_first_value("SELECT COUNT(*) FROM sqlite_sequence WHERE seq > 0")
      return if leftovers.empty? && counters.zero?

      db.transaction do
        # FK checks wait until commit, when every table is empty, so delete order does not matter
        db.execute("PRAGMA defer_foreign_keys = ON")
        tables.each { |t| db.execute("DELETE FROM \"#{t}\"") }
        # Restart every id at 1, as on a fresh db:test:prepare
        db.execute("DELETE FROM sqlite_sequence")
      end
      Rails.logger.warn("[SqliteSnapshotStrategy] live db was not fresh; before the snapshot removed leftover rows #{leftovers} " \
                        "and reset #{counters} id counter(s)")
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
