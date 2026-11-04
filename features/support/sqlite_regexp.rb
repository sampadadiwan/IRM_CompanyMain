# MySQL's `REGEXP` operator on the SQLite test database. SQLite parses `x REGEXP y` but ships no
# regexp() function, so app SQL written for MySQL (e.g. NoteSummarizerAgent's
# `tags NOT REGEXP '(^|,)summary(,|$)'`) raised "no such function: REGEXP" in Cucumber only. The
# production (MySQL) path is untouched; this registers the function on every SQLite connection.
require "sqlite3"

module SqliteRegexpFunction
  # Registers regexp(pattern, value) on one raw SQLite connection
  def self.register(raw_connection)
    raw_connection.create_function("regexp", 2) do |func, pattern, value|
      # NULL in, NULL out - as MySQL answers `NULL REGEXP 'x'`
      func.result = if pattern.nil? || value.nil?
                      nil
                    else
                      # MySQL compares non-binary strings case-insensitively (default collation)
                      Regexp.new(pattern.to_s, Regexp::IGNORECASE).match?(value.to_s) ? 1 : 0
                    end
    end
  end

  # Every connection the adapter opens from now on (the server thread's pool included)
  def configure_connection
    super
    SqliteRegexpFunction.register(@raw_connection)
  end
end

ActiveSupport.on_load(:active_record_sqlite3adapter) { prepend SqliteRegexpFunction }

# Connections already open when this file loads were configured before the prepend
ActiveRecord::Base.connection_handler.each_connection_pool do |pool|
  pool.connections.each do |conn|
    SqliteRegexpFunction.register(conn.raw_connection) if conn.adapter_name.casecmp?("sqlite")
  end
end
