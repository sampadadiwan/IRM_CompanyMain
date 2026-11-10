# One allocation engine per fund at a time, across every Sidekiq thread, process and box.
#
# A MySQL named lock ("allocation_fund:<id>") is held on the engine's own connection for the whole
# engine call. MySQL frees a named lock the moment the connection that holds it closes, so a run whose
# process is killed (watchdog, out-of-memory, deploy restart) never leaves the lock behind. That makes
# the lock the one reliable answer to "is a run on this fund really executing right now?" -- a run's
# status cannot answer it, because a killed run never gets to write one.
#
#   AllocationFundLock.hold(fund.id) { |taken| ... }  # taken is false when another engine holds it
#   AllocationFundLock.held?(fund.id)                  # true while some engine is running on the fund
#
# Why it exists: allocation runs 3499 and 3500 (fund 316, 2026-11-10) ran together, each deleted the
# other's entries and both inserted theirs -- see docs/modules/allocation/allocation_process.md, "One run per fund at a time".
#
# SQLite (the test database) has no named locks: hold always yields true and held? is always false.
# Scenarios make a fund look busy by stubbing these two methods.
module AllocationFundLock
  module_function

  def lock_name(fund_id)
    "allocation_fund:#{fund_id}"
  end

  # Yields whether the lock was taken; releases it afterwards. Never waits: a second engine on the
  # same fund is refused straight away rather than queued behind the first.
  def hold(fund_id)
    name = lock_name(fund_id)
    # GET_LOCK belongs to a connection, so take and release it on the one connection checked out
    # here. Inside a Sidekiq job this is the thread's own leased connection, which the engine keeps
    # using for its primary-DB work, so the lock lives exactly as long as the engine call.
    ActiveRecord::Base.with_connection do |connection|
      # Not a MySQL connection: nothing to contend with, so treat the lock as taken
      taken = !mysql?(connection) || statement(connection, ["SELECT GET_LOCK(?, 0)", name]).to_i == 1
      begin
        yield taken
      ensure
        # Only release a lock this call actually took
        statement(connection, ["SELECT RELEASE_LOCK(?)", name]) if taken && mysql?(connection)
      end
    end
  end

  # True while an engine on some connection holds the fund's lock
  def held?(fund_id)
    ActiveRecord::Base.with_connection do |connection|
      # SQLite: no named locks, so nothing can be seen as holding one
      next false unless mysql?(connection)

      # IS_USED_LOCK returns the holder's connection id, or NULL when the lock is free
      !statement(connection, ["SELECT IS_USED_LOCK(?)", lock_name(fund_id)]).nil?
    end
  end

  # uncached: jobs and requests run with the query cache on, and a SELECT served from the cache never
  # reaches MySQL, so the lock would be neither taken, released nor seen
  def statement(connection, sql_and_binds)
    connection.uncached { connection.select_value(ActiveRecord::Base.sanitize_sql(sql_and_binds)) }
  end

  def mysql?(connection)
    connection.adapter_name.casecmp?("mysql2")
  end
end
