# frozen_string_literal: true

# Steps for features/misc/dr_drill_report.feature. The run data is the 2026-11-08 staging drill's
# real figures, built in memory; nothing reads AWS, a transcript or a run directory.

# The 22 checks dr:verify printed on each server that day; the first server is 0.4 h, the second
# 0.0 h on data freshness, and both warned on the missing backup schedule.
def dr_1039_checks(age)
  [["✅", "prometheus_exporter process — 2 process(es)"], ["✅", "Nginx active — active"],
   ["✅", "Puma process — 1 process(es)"], ["✅", "HTTP db_check (nginx→puma→MySQL) — HTTP 200"],
   ["✅", "HTTP redis_check (nginx→puma→Redis cache) — HTTP 200"],
   ["✅", "HTTP elastic_check (nginx→puma→Elasticsearch) — HTTP 200"],
   ["✅", "HTTP disk_check (root filesystem <95%) — HTTP 200"],
   ["✅", "HTTP website apex (altconnects.com) — serving public/website"],
   ["✅", "HTTP website alias (www.altconnects.com) — redirects to altconnects.com"],
   ["✅", "HTTP xirr_check (xirr_py docker) — HTTP 200"], ["✅", "Sidekiq workers registered — 2 process(es)"],
   ["✅", "Migrations current"], ["✅", "Restored data freshness — newest users/documents row is #{age}h old"],
   ["✅", "S3 app bucket reachable — docs.altx.com.staging"], ["✅", "Primary mysqld (10.0.3.88) — active"],
   ["✅", "Primary docker: elasticsearch — running"], ["✅", "Primary docker: redis-stack-server — running"],
   ["✅", "Primary backup cron armed — /etc/db_backup_enabled present"],
   ["⚠️", "Primary backup cron installed — no /etc/cron.d/irm-db-backup — pre-bake AMI?"],
   ["✅", "Replica mysqld (10.0.4.217) — active"], ["✅", "Replica backup cron disarmed"],
   ["✅", "Replication live round-trip — Ok"]]
end

DR_1039_STEP_SECONDS = [
  ["Phase 1/9 · Refresh Pulumi stack configuration", 3], ["Phase 2/9 · Provision infrastructure (pulumi up)", 160],
  ["Phase 3/9 · Rewrite config with the new host addresses", 1], ["Phase 4/9 · Commit and push the DR branch (dr_drill_in_2026_11_08_1039)", 2],
  ["Phase 5/9 · Deploy the application to both app servers", 360], ["Phase 6/9 · Take traffic offline (nginx maintenance mode)", 9],
  ["Phase 7/9 · Restore the database from S3 backups", 119], ["Phase 8/9 · Rebuild the search index", 1],
  ["Phase 9/9 · Restore traffic and verify the recovered stack", 69]
].freeze

def dr_phases(count = DR_1039_STEP_SECONDS.size, open_last: false)
  t = Time.utc(2026, 11, 8, 5, 9, 13)
  DR_1039_STEP_SECONDS.first(count).each_with_index.map do |(title, secs), i|
    started = t
    t += secs
    [title, started, open_last && i == count - 1 ? nil : t]
  end
end

Given("the 2026-11-08 staging drill's run data") do
  @dr_run = { phases: dr_phases, result: "PASSED", drill: true,
              scorecard: { "ip-10-0-1-182" => dr_1039_checks("0.4"), "ip-10-0-2-46" => dr_1039_checks("0.0") } }
end

Given("a staging drill that failed during step {int} before verification") do |step|
  @dr_run = { phases: dr_phases(step, open_last: true), result: "FAILED", drill: true, scorecard: {} }
end

Given("only the first server reports {string}") do |line|
  @dr_run[:scorecard]["ip-10-0-1-182"] << ["✅", line]
end

Given("both servers report {string}") do |line|
  @dr_run[:scorecard].each_value { |lines| lines << ["✅", line] }
end

Given("the run was a real recovery") do
  @dr_run[:drill] = false
end

Given("only the second server warns on {string}") do |label|
  # The first server's line for that check becomes a pass
  @dr_run[:scorecard]["ip-10-0-1-182"].map! { |icon, line| line.start_with?(label) ? ["✅", "#{label} — present"] : [icon, line] }
end

Given("every check passed") do
  @dr_run[:scorecard].each_value { |lines| lines.map! { |_, line| ["✅", line] } }
end

Given("the first server fails {string}") do |line|
  label = line.split(" — ").first
  @dr_run[:scorecard]["ip-10-0-1-182"].map! { |icon, l| l.start_with?(label) ? ["❌", line] : [icon, l] }
end

When("the report model is built") do
  phases = @dr_run[:phases]
  finished = phases.last[2] || (phases.last[1] + 60)
  # The 1039 run's rebuild time was 12:04 = 724 s from its first phase's start (13:17: 8:36)
  finished = phases.first[1] + (@dr_run[:rebuild_seconds] || 724) if @dr_run[:result] == "PASSED"
  @dr_model = Dr::ReportModel.build(
    phases: phases, scorecard: @dr_run[:scorecard], result: @dr_run[:result],
    evidence: { "Infrastructure provisioned in ap-south-2" => ["Pulumi update #0", "pulumi stack history"] },
    stack: "staging", region: "ap-south-2", env_variant: "in", branch: "dr_drill_in_2026_11_08_1039",
    started_at: phases.first[1], finished: finished, drill: @dr_run[:drill], teardown: true, executed_by: "thimmaiah@Inspiron",
    recovery_point: @dr_run[:recovery_point]
  )
end

Then("the headline is {string}") do |text|
  expect(@dr_model.headline).to eq(text)
end

Then("the tiles read {string}, {string}, {string} and {string}") do |a, b, c, d|
  expect(@dr_model.tiles.map(&:first)).to eq([a, b, c, d])
end

Then("needs attention lists {int} item: {string} seen on {string}") do |count, name, hosts|
  expect(@dr_model.attention.size).to eq(count)
  expect(@dr_model.attention.first).to include(name: name, hosts: hosts)
end

Then("needs attention is empty") do
  expect(@dr_model.attention).to be_empty
end

Then("the first attention item is {string}") do |name|
  expect(@dr_model.attention.first[:name]).to eq(name)
end

Then("the check groups are {string}") do |names|
  expect(@dr_model.groups.pluck(:name).join(", ")).to eq(names)
end

Then("there are {int} check rows with a result for each of {int} servers") do |rows, servers|
  all = @dr_model.groups.flat_map { |g| g[:rows] }
  expect(all.size).to eq(rows)
  # Plain Ruby: inside Cucumber, `all` is Capybara's finder, not RSpec's matcher
  expect(all.reject { |r| r[:cells].values.compact.size == servers }).to be_empty
end

Then("every step has a plain name and a {string} explanation") do |_label|
  expect(@dr_model.steps.reject { |s| s[:name].present? && s[:does].present? && s[:name] !~ /\APhase/ }).to be_empty
end

Then("step {int} is named {string}") do |n, name|
  expect(@dr_model.steps[n - 1][:name]).to eq(name)
end

Then("the {string} row has no result for the second server") do |name|
  row = @dr_model.groups.flat_map { |g| g[:rows] }.find { |r| r[:name] == name }
  expect(row[:cells]["ip-10-0-2-46"]).to be_nil
end

Then("the {string} group has a row {string}") do |group, name|
  rows = @dr_model.groups.find { |g| g[:name] == group }&.dig(:rows) || []
  expect(rows.pluck(:name)).to include(name)
end

When("the check label {string} is looked up") do |label|
  @dr_lookup = Dr::ReportCatalog.check(label)
end

Then("it is shown as {string} under {string}") do |name, group|
  expect(@dr_lookup.last).to eq(name)
  expect(@dr_lookup.first[:group]).to eq(group)
end

Then("the plain words mention {string}") do |text|
  expect(@dr_model.plain_words.join(" ")).to include(text)
end

Then("the plain words do not mention {string}") do |text|
  expect(@dr_model.plain_words.join(" ")).not_to include(text)
end

Then("the report says verification was not reached") do
  expect(@dr_model.verified).to be(false)
  expect(@dr_model.plain_words.join(" ")).to include("no checks ran")
end

When("every check label in dr:verify and every step in setup_infra is looked up") do
  verify = Rails.root.join("lib/tasks/dr_verify.rake").read
  # Literal labels plus the interpolated ones (a sample value stands in for #{...});
  # the HTTP labels live in a hash, so read those too
  labels = verify.scan(/(?:check|guarded)\.call\("([^"]+)"/).flatten +
           verify.scan(/drill \? "([^"]+)" : "([^"]+)"/).flatten +
           verify.scan(/=> "(HTTP [^"]+)"/).flatten +
           verify.scan(/label = "([^"]+)"/).flatten
  labels = labels.map { |l| l.gsub(/#\{[^}]*\}/, "x") }.uniq
  steps = Rails.root.join("lib/tasks/aws_utils.rb").read.scan(/dr_phase "([^"]+)"/).flatten
  @dr_uncovered = labels.select { |l| Dr::ReportCatalog.check(l).first[:group] == "Other checks" } +
                  steps.reject { |t| Dr::ReportCatalog::STEPS.any? { |e| t.match?(e[:match]) } }
  @dr_label_count = labels.size + steps.size
end

Then("none of them falls into Other checks") do
  expect(@dr_label_count).to be > 25
  expect(@dr_uncovered).to be_empty
end

When("the report is rendered") do
  @dr_html = Dr::ReportRender.html(@dr_model)
  @dr_md = Dr::ReportRender.markdown(@dr_model)
end

Then("the HTML has no dark theme and no external links") do
  expect(@dr_html).not_to include("prefers-color-scheme")
  expect(@dr_html).not_to match(%r{https?://})
end

Then("the HTML shows the badge {string}") do |text|
  expect(@dr_html).to match(%r{<span class="badge ok">.*#{text}</span>})
end

Then("the Markdown and HTML reports list the same sections in the same order") do
  html_sections = @dr_html.scan(%r{<h2>(.*?)</h2>}m).flatten.map { |h2| h2.gsub(/<[^>]+>/, "").strip }
  md_sections = @dr_md.lines.grep(/\A## /).map { |l| l.delete_prefix("## ").strip }
  expect(html_sections).to eq(Dr::ReportModel::SECTIONS)
  expect(md_sections).to eq(Dr::ReportModel::SECTIONS)
end

Then("the HTML shows {string} as text") do |escaped|
  expect(@dr_html).to include(escaped)
end

Then("the HTML contains no {string} tag") do |tag|
  expect(@dr_html).not_to include(tag)
end

Then("needs attention includes {string} seen on {string}") do |name, hosts|
  expect(@dr_model.attention).to include(a_hash_including(name: name, hosts: hosts))
end

Given("the 2026-11-08 13:17 staging drill, recovered to backup {string} at {int}:{int}:{int} UTC") do |key, hh, mm, ss|
  # 13:17 IST = 07:47:56 UTC; rebuild 8:36
  start = Time.utc(2026, 11, 8, 7, 47, 56)
  base = dr_phases.first[1]
  phases = dr_phases.map { |title, s, e| [title, start + (s - base), start + (e - base)] }
  @dr_run = { phases: phases, result: "PASSED", drill: true, rebuild_seconds: 516,
              scorecard: { "ip-10-0-1-182" => dr_1039_checks("0.9"), "ip-10-0-2-46" => dr_1039_checks("0.9") },
              recovery_point: { full: "2026-11-07_230001-full", incr: key, at: Time.utc(2026, 11, 8, hh, mm, ss) } }
end

Then("the recovery point is {string}: {string}") do |verdict, achieved|
  rpo = @dr_model.objectives.find { |o| o[:name] == "Recovery point (RPO)" }
  expect(rpo[:status]).to eq({ "met" => :ok, "not met" => :warn, "not reached" => :fail }.fetch(verdict))
  expect(rpo[:achieved]).to eq(achieved)
end

Then("the recovery time is {string}: {string}") do |verdict, achieved|
  rto = @dr_model.objectives.find { |o| o[:name] == "Recovery time (RTO)" }
  expect(rto[:status]).to eq({ "met" => :ok, "not met" => :warn, "not reached" => :fail }.fetch(verdict))
  expect(rto[:achieved]).to eq(achieved)
end

Given("a transcript where the primary restored {string} and {string}") do |full, incr|
  @dr_transcript = Tempfile.new(["dr", ".log"])
  @dr_transcript.write(<<~LOG)
    01 [replica] Found latest full backup: 2026-11-01_230001-full
    01 [primary] Found latest full backup: #{full}
    01 [primary] Found latest incremental backup to apply:
    01 [primary]   FULL            #{full}
    01 [primary]   INCREMENTAL     #{incr}
  LOG
  @dr_transcript.flush
end

When("the recovery point is read from it") do
  require Rails.root.join("lib/tasks/aws_utils").to_s
  @dr_point = Object.new.extend(AwsUtils).parse_recovery_point(@dr_transcript.path)
ensure
  @dr_transcript&.close!
end

Then("the recovery point is {int}-{int}-{int} {int}:{int}:{int} UTC from {string}") do |y, mo, d, hh, mm, ss, key|
  expect(@dr_point[:at]).to eq(Time.utc(y, mo, d, hh, mm, ss))
  expect(@dr_point[:incr]).to eq(key)
end

Given("the rebuild took {int} seconds") do |seconds|
  @dr_run[:rebuild_seconds] = seconds
end
