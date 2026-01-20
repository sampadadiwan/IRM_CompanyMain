# AccountEntryAllocationJob.perform_now 317, Date.parse("Tue, 01 Apr 2025"), Date.parse("Mon, 30 Jun 2025"), rule_for: "", tag_list: nil, run_allocations: true, explain: true, user_id: 484, generate_soa: false, template_id: "54288", fund_ratios: false, sample: false, allocation_run_id: 2080

# rubocop:disable Style/ClassVars
module AccountEntryAllocation
  module WithScratchSqlite
    # We maintain a global registry of connection pools keyed by file path.
    # This allows multiple threads to share the same pool if they use the same file,
    # while different jobs use different pools.
    @@sqlite_pools = {}
    @@sqlite_pools_mutex = Mutex.new

    def with_scratch_sqlite(path)
      # Optimization: If this thread already has a connection to a SQLite DB,
      # just reuse it (supports nesting).
      return yield if Thread.current[:sqlite_scratch_connection]

      # 1. Get or create a connection pool for this specific SQLite file
      pool = @@sqlite_pools_mutex.synchronize do
        @@sqlite_pools[path] ||= begin
          Rails.logger.debug { "Creating new SQLite connection pool for #{path}" }
          config_hash = { adapter: "sqlite3", database: path, pool: 10, timeout: 5000 }
          db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new("scratch", "sqlite", config_hash)
          # In modern Rails, ConnectionPool expects a PoolConfig.
          # We use the internal PoolConfig class to wrap the DB configuration.
          pool_config = ActiveRecord::ConnectionAdapters::PoolConfig.new(ActiveRecord::Base, db_config, :writing, :default)
          ActiveRecord::ConnectionAdapters::ConnectionPool.new(pool_config)
        end
      end

      # 2. Checkout a connection and assign it to a thread-local variable.
      # This is the key: ApplicationRecordSqlite.connection will check this variable.
      pool.with_connection do |conn|
        # Initialize the connection if it's new (WAL mode, etc.)
        unless conn.instance_variable_get(:@sqlite_initialized)
          conn.execute("PRAGMA journal_mode=WAL;")
          conn.execute("PRAGMA synchronous=OFF;")
          conn.instance_variable_set(:@sqlite_initialized, true)
        end

        Thread.current[:sqlite_scratch_connection] = conn
        begin
          yield
        ensure
          Thread.current[:sqlite_scratch_connection] = nil
        end
      end
    end

    # Helper to prune unused pools if needed
    def self.clear_all_sqlite_pools
      @@sqlite_pools_mutex.synchronize do
        @@sqlite_pools.each_value(&:disconnect!)
        @@sqlite_pools.clear
      end
    end
  end
end
# rubocop:enable Style/ClassVars
