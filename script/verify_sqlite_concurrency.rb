# Usage: bundle exec rails runner script/verify_sqlite_concurrency.rb

# rubocop:disable Style/MixinUsage
require 'fileutils'
require 'sqlite3'
require 'securerandom'

# Define a test model that uses ApplicationRecordSqlite
# This ensures we are testing the model layer's connection resolution
class StressData < ApplicationRecordSqlite
  self.table_name = 'stress_data'
  # Remove any validations inherited from parent
  _validators.clear
  # Override association to be optional
  belongs_to :fund, class_name: 'FundSqlite', optional: true
end

def setup_db(path, name)
  SQLite3::Database.new(path) do |db|
    db.execute "CREATE TABLE IF NOT EXISTS meta_info (name varchar(30));"
    db.execute "INSERT INTO meta_info VALUES ('#{name}');"
    # Create table matching our model structure
    db.execute "CREATE TABLE IF NOT EXISTS stress_data (id INTEGER PRIMARY KEY AUTOINCREMENT, thread_id integer, fund_id integer, data varchar(50), created_at datetime, updated_at datetime);"
    # Create funds table
    db.execute "CREATE TABLE IF NOT EXISTS funds (id INTEGER PRIMARY KEY, name varchar(50));"
    db.execute "INSERT INTO funds (id, name) VALUES (1, 'Dummy Fund');"
  end
end

puts "--- Starting Full Isolation Stress Test (Models + Isolation) ---"
puts "Running with 10 threads, mix of distinct and shared paths..."

THREAD_COUNT = 10
DB_COUNT = 5
PATHS = (1..DB_COUNT).map { |i| Rails.root.join("tmp/stress_db_#{i}.sqlite3").to_s }
NAMES = (1..DB_COUNT).map { |i| "DB_#{i}" }

PATHS.each_with_index do |path, i|
  FileUtils.rm_f(path)
  setup_db(path, NAMES[i])
end

include AccountEntryAllocation::WithScratchSqlite

results = Array.new(THREAD_COUNT)
threads = []

THREAD_COUNT.times do |i|
  threads << Thread.new do
    db_idx = rand(DB_COUNT)
    path = PATHS[db_idx]
    expected_name = NAMES[db_idx]

    sleep(rand * 0.5)

    with_scratch_sqlite(path) do
      # We intentionally do NOT manually get connection here.
      # We want StressData to find it automatically.

      begin
        # 1. READ CHECK (Raw SQL via Model connection to verify adapter check)
        # This triggers ApplicationRecordSqlite.connection -> adapter check
        rows = StressData.connection.execute("SELECT name FROM meta_info")
        val = begin
          rows.first['name']
        rescue StandardError
          rows.first[0]
        end

        raise "Read Mismatch: Expected #{expected_name}, got #{val}" unless val == expected_name

        # 2. INSERT (ActiveRecord)
        unique_val = "Thread-#{i}-#{SecureRandom.hex(4)}"

        # Debug connection info
        active_conn = StressData.connection
        # puts "Thread #{i} Model Conn: #{active_conn.object_id} DB: #{active_conn.raw_connection.filename}" rescue nil

        # Verify tables visibility
        tables = active_conn.tables
        unless tables.include?('stress_data')
          puts "Thread #{i} TABLES: #{tables.inspect}"
          raise "Table stress_data missing from connection metadata!"
        end

        # FORCE CLEAR CACHE (Workaround test)
        # StressData.reset_column_information

        StressData.create!(thread_id: i, data: unique_val, fund_id: 1)

        # 3. VERIFY INSERT ISOLATION
        sleep(rand * 0.2)
        # Find using AR
        found = StressData.find_by(thread_id: i)

        raise "Insert Mismatch: Expected #{unique_val}, got #{found&.data}" unless found && found.data == unique_val

        # 4. UPDATE (ActiveRecord)
        updated_val = "#{unique_val}-UPDATED"
        found.update!(data: updated_val)

        # Reload to verify persistence
        found.reload
        raise "Update Mismatch: Expected #{updated_val}, got #{found.data}" unless found.data == updated_val

        # 5. DELETE (ActiveRecord)
        found.destroy

        raise "Delete Failed: Row still exists" if StressData.exists?(thread_id: i)

        results[i] = true
      rescue StandardError => e
        puts "Thread #{i} ERROR on #{expected_name}: #{e.message}"
        puts e.backtrace.join("\n") if e.message.include?("Safety Violation")
        results[i] = false
      end

      sleep(rand * 0.5)
    end
  end
end

threads.each(&:join)

# Cleanup
PATHS.each { |path| FileUtils.rm_f(path) }

if results.all?
  puts "--- SUCCESS: Full Model Isolation Verified! ---"
else
  puts "--- FAILED: #{results.count(false)} threads failed. ---"
end

# rubocop:enable Metrics/BlockLength
# rubocop:enable Style/MixinUsage
