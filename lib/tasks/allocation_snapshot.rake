# Snapshots a fund's account entries into a side table, and diffs two snapshots, so a change to
# the allocation engine or its formulas can be checked against what the same run produced before.
# Built for docs/technical/incremental_allocation_history.md: snapshot, re-run a window, snapshot
# again, and require an empty diff.
#
# Usage:
#   bundle exec rake allocation_snapshot:take[319,a_prod]
#   bundle exec rake allocation_snapshot:list[319]
#   bundle exec rake allocation_snapshot:diff[319,b_old_code,c_new_code] FROM=2026-08-01 TO=2026-08-31
#
# A snapshot holds every live row (generated and uploaded), so it doubles as a restore point: a run
# hard-deletes the entries in its window before regenerating them. The diff compares generated rows
# only, optionally limited to FROM..TO on reporting_date.
#
# TOLERANCE= (in cents, default 0.0001) absorbs float rounding: the scratch SQLite DB sums amounts as
# floats, so the same total reached by a different sequence of additions can differ in the 8th decimal.
#
# Everything runs as SQL inside MySQL. account_entries is far too large to pull into Ruby.
# A validation tool for a copy of production: each snapshot is a full copy of a fund's entries in a new
# table (1.8 million rows for fund 317), so do not run it against the production database.
namespace :allocation_snapshot do
  # Columns that identify an entry. Rows sharing all of them are compared as one key: same row count
  # and the same summed amounts. explanation, notes, json_fields and the run/timestamp columns are
  # left out, they differ between runs even when the numbers do not.
  def snapshot_key_columns
    %w[fund_formula_id name entry_type reporting_date capital_commitment_id folio_id parent_type parent_id cumulative rule_for]
  end

  def snapshot_amount_columns
    %w[amount_cents folio_amount_cents tracking_amount_cents]
  end

  def snapshot_table(fund_id, label)
    abort "label must be letters, digits or underscores" unless label.to_s.match?(/\A\w{1,40}\z/)

    "ae_snapshot_#{Integer(fund_id)}_#{label}"
  end

  desc "Copy a fund's live account entries into ae_snapshot_<fund>_<label>"
  task :take, %i[fund_id label] => :environment do |_t, args|
    fund_id = Integer(args[:fund_id])
    table = snapshot_table(fund_id, args[:label])
    conn = ActiveRecord::Base.connection
    abort "#{table} already exists. Pick another label, or DROP it first." if conn.table_exists?(table)

    started = Time.zone.now
    conn.execute("CREATE TABLE #{table} AS SELECT * FROM account_entries WHERE fund_id = #{fund_id} AND deleted_at IS NULL")
    conn.execute("ALTER TABLE #{table} ADD INDEX idx_snapshot_reporting_date (reporting_date), " \
                 "COMMENT = #{conn.quote("fund #{fund_id} taken #{started.iso8601}")}")

    puts "#{table} created in #{(Time.zone.now - started).round(1)}s"
    conn.select_rows("SELECT `generated`, COUNT(*), MIN(reporting_date), MAX(reporting_date) FROM #{table} GROUP BY `generated`").each do |generated, count, min, max|
      puts format("  generated=%<g>s  %<c>9d rows  %<min>s to %<max>s", g: generated, c: count, min:, max:)
    end
  end

  desc "List the snapshots taken for a fund"
  task :list, %i[fund_id] => :environment do |_t, args|
    conn = ActiveRecord::Base.connection
    pattern = conn.quote("ae\\_snapshot\\_#{Integer(args[:fund_id])}\\_%")
    conn.select_rows("SELECT table_name, table_comment FROM information_schema.tables " \
                     "WHERE table_schema = DATABASE() AND table_name LIKE #{pattern} ORDER BY create_time").each do |name, comment|
      puts "#{name}  #{conn.select_value("SELECT COUNT(*) FROM #{name}")} rows  (#{comment})"
    end
  end

  desc "Diff the generated entries of two snapshots of a fund (FROM=/TO= limit reporting_date, TOLERANCE= cents)"
  task :diff, %i[fund_id from_label to_label] => :environment do |_t, args|
    fund_id = Integer(args[:fund_id])
    from_table = snapshot_table(fund_id, args[:from_label])
    to_table = snapshot_table(fund_id, args[:to_label])
    conn = ActiveRecord::Base.connection
    [from_table, to_table].each { |t| abort "#{t} does not exist" unless conn.table_exists?(t) }
    tolerance = BigDecimal(ENV.fetch("TOLERANCE", "0.0001"))

    where = ["`generated` = 1"]
    where << "reporting_date >= #{conn.quote(Date.parse(ENV['FROM']))}" if ENV["FROM"].present?
    where << "reporting_date <= #{conn.quote(Date.parse(ENV['TO']))}" if ENV["TO"].present?
    where = where.join(" AND ")

    keys = snapshot_key_columns.map { |c| "`#{c}`" }.join(", ")
    amounts = snapshot_amount_columns
    selected = "#{keys}, #{amounts.map { |c| "`#{c}`" }.join(', ')}"

    puts "Comparing generated entries #{from_table} -> #{to_table} (#{where}), tolerance #{tolerance.to_s('F')} cents"
    [from_table, to_table].each do |t|
      rows, amount = conn.select_rows("SELECT COUNT(*), SUM(amount_cents) FROM #{t} WHERE #{where}").first
      puts format("  %-45<t>s %<r>9d rows  amount_cents %<a>s", t:, r: rows, a: amount)
    end

    # One row per key: row counts and summed amounts on each side, plus the largest amount delta
    per_key = <<~SQL.squish
      SELECT #{keys}, SUM(side = 'from') AS from_rows, SUM(side = 'to') AS to_rows,
             #{amounts.map { |c| "SUM(IF(side = 'from', IFNULL(`#{c}`, 0), 0)) AS from_#{c}, SUM(IF(side = 'to', IFNULL(`#{c}`, 0), 0)) AS to_#{c}" }.join(', ')},
             GREATEST(#{amounts.map { |c| "ABS(SUM(IF(side = 'from', IFNULL(`#{c}`, 0), 0)) - SUM(IF(side = 'to', IFNULL(`#{c}`, 0), 0)))" }.join(', ')}) AS max_delta
      FROM (SELECT 'from' AS side, #{selected} FROM #{from_table} WHERE #{where}
            UNION ALL
            SELECT 'to' AS side, #{selected} FROM #{to_table} WHERE #{where}) both_sides
      GROUP BY #{keys}
    SQL
    mismatched = "SELECT * FROM (#{per_key}) k WHERE from_rows <> to_rows OR max_delta > #{tolerance.to_s('F')}"

    rounding = conn.select_value("SELECT COUNT(*) FROM (#{per_key}) k WHERE from_rows = to_rows AND max_delta > 0 AND max_delta <= #{tolerance.to_s('F')}")
    by_name = conn.select_rows(<<~SQL.squish)
      SELECT name, COUNT(*), SUM(from_rows <> to_rows), MAX(max_delta) FROM (#{mismatched}) d
      GROUP BY name ORDER BY MAX(max_delta) DESC
    SQL

    puts "  #{rounding} keys differ only by rounding (within tolerance)" if rounding.to_i.positive?
    if by_name.empty?
      puts "IDENTICAL: every generated entry matches."
      next
    end

    puts "DIFFERENT: #{by_name.sum { |r| r[1] }} keys across #{by_name.size} names"
    puts "  #{'name'.ljust(60)} #{'keys'.rjust(6)} #{'row count differs'.rjust(17)} #{'max delta (cents)'.rjust(22)}"
    by_name.first(50).each do |name, count, count_diff, max_delta|
      puts format("  %-60<n>s %6<k>d %17<c>d %22<d>s", n: name.to_s.truncate(60), k: count, c: count_diff, d: max_delta.to_d.round(4).to_s("F"))
    end
    puts "  ... #{by_name.size - 50} more names" if by_name.size > 50

    dir = Rails.root.join("tmp/allocation_snapshots")
    FileUtils.mkdir_p(dir)
    path = dir.join("diff_#{fund_id}_#{args[:from_label]}_#{args[:to_label]}.csv")
    CSV.open(path, "w") do |csv|
      csv << (snapshot_key_columns + %w[from_rows to_rows] + amounts.flat_map { |c| ["from_#{c}", "to_#{c}"] } + %w[max_delta])
      # Streamed so a large diff never sits in memory. cast: false keeps decimal(30,8) amounts as
      # MySQL prints them; casting goes through Float and drops the digits a diff is looking for.
      conn.raw_connection.query("#{mismatched} ORDER BY name, reporting_date, capital_commitment_id",
                                stream: true, cache_rows: false, as: :array, cast: false).each { |row| csv << row }
    end
    puts "Full diff written to #{path}"
  end
end
