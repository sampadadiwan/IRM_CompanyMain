#!/usr/bin/env ruby
# Parses log/bullet.log and log/test.log to produce a ranked N+1 report.
# Usage: ruby scripts/analyze_bullet_log.rb [bullet_log] [test_log]
#
# Output: tmp/n_plus_one_report.md

require "date"
require "fileutils"

BULLET_LOG = ARGV[0] || "log/bullet.log"
TEST_LOG   = ARGV[1] || "log/test.log"
REPORT     = "tmp/n_plus_one_report.md".freeze

# ── 1. Parse bullet.log ──────────────────────────────────────────────────────

# Each Bullet entry looks like:
#   2024-01-15 12:34:56[WARN] user: N+1 Query detected
#     Post => [:comments]
#     Add to your finder: :includes => [:comments]
#     Call stack:
#       app/controllers/posts_controller.rb:12:in `index'

Issue = Struct.new(:timestamp, :kind, :model, :associations, :add_includes, :call_stack, keyword_init: true)

issues = []
lines  = File.exist?(BULLET_LOG) ? File.readlines(BULLET_LOG) : []

# Actual log format (multi-line blocks separated by blank lines):
#   2026-05-25 11:32:33[WARN] user: thimmaiah
#   GET /boards/1
#   USE eager loading detected          <- or AVOID eager loading detected
#     Deal => [:deal_investors]
#     Add to your finder: ...           <- USE has this
#     Remove from your query: ...       <- AVOID has this
#   Call stack
#     app/foo.rb:34:in '...'

current = nil
lines.each do |raw|
  line = raw.chomp

  if (m = line.match(/^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s*\[?(WARN|ERROR)\]?/))
    # Start of a new Bullet block — push previous and open a fresh one
    issues << current if current
    current = Issue.new(
      timestamp: m[1],
      kind: nil, # filled in when we see the USE/AVOID line
      model: nil,
      associations: [],
      add_includes: nil,
      call_stack: []
    )

  elsif current
    stripped = line.strip

    # Kind detection: dedicated "USE/AVOID eager loading detected" line
    if stripped.match?(/\AUSE eager loading detected\z/i)
      current.kind = "n_plus_one"
    elsif stripped.match?(/\AAVOID eager loading detected\z/i)
      current.kind = "unused_eager_loading"

    # Model/association pair: "Post => [:comments]"
    elsif (m = stripped.match(/^(.+?)\s*=>\s*\[(.+)\]/))
      current.model        = m[1].strip
      current.associations = m[2].split(",").map { |a| a.strip.delete(":") }

    elsif stripped.start_with?("Add to your finder:")
      current.add_includes = stripped

    # Call stack lines contain .rb or .erb file paths
    elsif /\.(rb|erb):\d+/.match?(stripped)
      current.call_stack << stripped
    end
  end
end
issues << current if current
# Drop incomplete entries (no kind = malformed block)
issues.compact!
issues.reject! { |i| i.kind.nil? || i.model.nil? }

# ── 2. Build scenario timeline from test.log ──────────────────────────────────
# env.rb logs:  "Starting scenario: <name>"
# We record (timestamp_approx, scenario_name) pairs and later binary-search
# each Bullet issue's timestamp to find the closest preceding scenario.

ScenarioEntry = Struct.new(:line_no, :name)
scenario_timeline = []

if File.exist?(TEST_LOG)
  File.foreach(TEST_LOG).with_index do |raw, idx|
    if (m = raw.match(/Starting scenario:\s*(.+)/))
      scenario_timeline << ScenarioEntry.new(idx, m[1].strip)
    end
  end
end

# ── 3. Cross-reference: match each issue to a scenario by timestamp ──────────
# bullet.log timestamps are wall-clock; test.log doesn't embed timestamps but
# does embed the scenario name sequentially. We use the order of issues in
# bullet.log against the order of scenarios in test.log as a best-effort match.

def scenario_for(issue_index, scenario_timeline)
  return "unknown" if scenario_timeline.empty?

  # Each Bullet flush corresponds to one scenario's After hook.
  # Map issue index → scenario index (clamped to timeline length).
  idx = [issue_index, scenario_timeline.size - 1].min
  scenario_timeline[idx]&.name || "unknown"
end

# ── 4. Group by model+association for frequency ranking ──────────────────────

frequency = Hash.new { |h, k| h[k] = { count: 0, call_sites: Set.new, scenarios: Set.new } }
avoid_frequency = Hash.new { |h, k| h[k] = { count: 0, call_sites: Set.new } }

issues.each_with_index do |issue, i|
  key = "#{issue.model} => [#{issue.associations.join(', ')}]"
  if issue.kind == "n_plus_one"
    frequency[key][:count] += 1
    issue.call_stack.first(3).each { |cs| frequency[key][:call_sites] << cs }
    frequency[key][:scenarios] << scenario_for(i, scenario_timeline)
  else
    avoid_frequency[key][:count] += 1
    issue.call_stack.first(2).each { |cs| avoid_frequency[key][:call_sites] << cs }
  end
end

# Genuine AVOID = appears only in AVOID, never in USE → safe to remove or safelist
conflicted_avoids, genuine_avoids = avoid_frequency.partition { |key, _| frequency.key?(key) }
# Conflicted AVOID = appears in both USE and AVOID → means the preload IS needed in some paths; safelist, don't remove

unused = issues.select { |i| i.kind == "unused_eager_loading" }

# ── 5. Write markdown report ─────────────────────────────────────────────────

FileUtils.mkdir_p("tmp")
File.open(REPORT, "w") do |f|
  f.puts "# N+1 Query Report"
  f.puts "_Generated: #{Time.zone.now.strftime('%Y-%m-%d %H:%M:%S')}_"
  f.puts "_Source: `#{BULLET_LOG}` + `#{TEST_LOG}`_"
  f.puts
  f.puts "## Summary"
  f.puts "- **Total USE N+1 issues detected:** #{issues.count { |i| i.kind == 'n_plus_one' }}"
  f.puts "- **Unique USE model/association pairs:** #{frequency.size}"
  f.puts "- **Total AVOID warnings:** #{unused.size}"
  f.puts "- **Genuine AVOIDs (only AVOID, never USE — safe to remove/safelist):** #{genuine_avoids.size}"
  f.puts "- **Conflicted AVOIDs (also appear as USE — SAFELIST, do not remove):** #{conflicted_avoids.size}"
  f.puts

  f.puts "## N+1 Queries — Ranked by Frequency"
  f.puts
  if frequency.empty?
    f.puts "_No N+1 queries detected. Either the suite hasn't run yet or everything is clean!_"
  else
    frequency.sort_by { |_, v| -v[:count] }.each_with_index do |(key, data), rank|
      f.puts "### #{rank + 1}. `#{key}` (#{data[:count]}×)"
      f.puts
      f.puts "**Fix:** Add `.includes(#{data[:scenarios].first&.then { '' }})` — see add-to-finder hint in bullet.log"
      unless data[:call_sites].empty?
        f.puts
        f.puts "**Top call sites:**"
        data[:call_sites].first(5).each { |cs| f.puts "- `#{cs}`" }
      end
      unless data[:scenarios].empty?
        f.puts
        f.puts "**Triggered by scenarios:**"
        data[:scenarios].first(10).each { |s| f.puts "- #{s}" }
      end
      f.puts
    end
  end

  unless conflicted_avoids.empty?
    f.puts "## Conflicted AVOIDs — SAFELIST ONLY, do not remove"
    f.puts "_These appear as both AVOID (some paths) and USE N+1 (other paths). The preload IS needed; add to Bullet safelist._"
    f.puts
    conflicted_avoids.sort_by { |_, v| -v[:count] }.each do |(key, data)|
      f.puts "### `#{key}` (AVOID #{data[:count]}×, USE #{frequency[key][:count]}×)"
      data[:call_sites].each { |cs| f.puts "- AVOID: `#{cs}`" }
      frequency[key][:call_sites].first(2).each { |cs| f.puts "- USE: `#{cs}`" }
      f.puts
    end
  end

  unless genuine_avoids.empty?
    f.puts "## Genuine AVOIDs — safe to remove or safelist"
    f.puts "_These ONLY appear as AVOID, never as USE. You can either remove the .includes or add to safelist._"
    f.puts
    genuine_avoids.sort_by { |_, v| -v[:count] }.each do |(key, data)|
      f.puts "### `#{key}` (#{data[:count]}×)"
      data[:call_sites].each { |cs| f.puts "- `#{cs}`" }
      f.puts
    end
  end

  unless unused.empty?
    f.puts "## Unused Eager Loading (raw — deduplicated above)"
    f.puts
    unused.each do |issue|
      f.puts "- `#{issue.model}` — #{issue.call_stack.first}"
    end
    f.puts
  end

  f.puts "## Raw Bullet Log Statistics"
  f.puts "- Total entries parsed: #{issues.size}"
  f.puts "- Scenarios in test.log: #{scenario_timeline.size}"
end

puts "Report written to #{REPORT}"
puts
puts
puts "Top 10 genuine USE N+1 offenders:"
frequency.sort_by { |_, v| -v[:count] }.first(10).each_with_index do |(key, data), i|
  puts "  #{i + 1}. #{key}  (#{data[:count]}×)"
end
puts
puts "Genuine AVOIDs (safe to remove — never appear as USE):"
genuine_avoids.sort_by { |_, v| -v[:count] }.first(10).each_with_index do |(key, data), i|
  puts "  #{i + 1}. #{key}  (#{data[:count]}×)"
end
puts
puts "Conflicted AVOIDs (safelist only — appear as BOTH avoid AND use):"
conflicted_avoids.sort_by { |_, v| -v[:count] }.first(10).each_with_index do |(key, data), i|
  puts "  #{i + 1}. #{key}  (AVOID #{data[:count]}×, USE #{frequency[key][:count]}×)"
end
