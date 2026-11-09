# frozen_string_literal: true

# Steps for features/misc/data_box_exporters.feature. Pure: unit text, scripts and YAML in memory,
# plus the repo's Prometheus / .env files. The alert-rule steps ("I read the provisioned Grafana
# alert rules", ...) live in clock_sync_monitoring_steps.rb and "the dashboard has one {string}
# row" in yjit_monitoring_steps.rb.

# The exporter with this binary name (DataBoxExporters::EXPORTERS)
def data_box_exporter(name)
  DataBoxExporters::EXPORTERS.find { |e| e.name == name } || raise("no data box exporter #{name.inspect}")
end

# A repo Prometheus config as text, for production.in / production.us
def data_box_repo_prometheus(env)
  Rails.root.join(DataBoxExporters::PROMETHEUS_FILES.fetch(env)).read
end

# --- Units and install script ------------------------------------------------------------------

When("the data box unit for {string} is rendered") do |name|
  @data_box_unit = DataBoxExporters.unit(data_box_exporter(name))
end

Then("the data box unit runs {string} listening on {string}") do |binary, listen|
  exec_start = @data_box_unit.lines.find { |l| l.start_with?("ExecStart=") }
  expect(exec_start).to start_with("ExecStart=#{binary} ")
  expect(exec_start).to include("--web.listen-address=#{listen}")
end

Then("the data box unit runs as the user {string}") do |user|
  expect(@data_box_unit.lines.map(&:chomp)).to include("User=#{user}", "Group=#{user}")
end

When("the data box install script for {string} is rendered") do |name|
  @data_box_script = DataBoxExporters.install_script(data_box_exporter(name))
end

Then("the data box install script verifies {string} before it installs the binary") do |checksums|
  verify_at = @data_box_script.index("sha256sum -c")
  install_at = @data_box_script.index("sudo install -m 0755")
  expect(@data_box_script).to include(checksums)
  expect(verify_at).to be_present
  expect(install_at).to be_present
  expect(verify_at).to be < install_at
  # set -e makes a failed check stop the script before the install line
  expect(@data_box_script.lines.first.strip).to eq("set -euo pipefail")
end

Then("the data box install script prints OK only after {string} serves {string}") do |path, metric|
  check_at = @data_box_script.index(path)
  ok_at = @data_box_script.index('echo "$state ')
  expect(@data_box_script).to include("grep '^#{metric}' >/dev/null")
  expect(check_at).to be < ok_at
end

# Regression (prod IN, 2026-11-09): under pipefail, `curl | grep -q` reports a served metric as
# missing once /metrics is bigger than the pipe buffer - elasticsearch_exporter's always is
Then("the data box install script never pipes into grep -q") do
  expect(@data_box_script).not_to match(/\|\s*grep -q/)
end

# --- mysqld_exporter memory collector ---------------------------------------------------------

Given("a data box mysqld_exporter unit:") do |text|
  @data_box_mysqld_unit = "#{text}\n"
end

When("the data box memory collector is added") do
  @data_box_collector = DataBoxExporters.add_memory_collector(@data_box_mysqld_unit)
end

Then("the data box collector change is {string}") do |status|
  expect(@data_box_collector[:status]).to eq(status.to_sym)
end

Then("the data box ExecStart line reads {string}") do |line|
  expect(@data_box_collector[:text].lines.map(&:chomp)).to include(line)
end

Then("every other data box unit line is unchanged") do
  before = @data_box_mysqld_unit.lines.reject { |l| l.start_with?("ExecStart=") }
  after = @data_box_collector[:text].lines.reject { |l| l.start_with?("ExecStart=") }
  expect(after).to eq(before)
end

# --- Prometheus push guard --------------------------------------------------------------------

Given("the live Prometheus config is the {string} repo config without the {string} and {string} jobs") do |env, *jobs|
  config = YAML.safe_load(data_box_repo_prometheus(env))
  config["scrape_configs"].reject! { |c| jobs.include?(c["job_name"]) }
  @data_box_live = config.to_yaml
end

Given("the live Prometheus config is the {string} repo config") do |env|
  @data_box_live = data_box_repo_prometheus(env)
end

Given("the live Prometheus config is the {string} repo config with the {string} job's targets changed") do |env, job|
  config = YAML.safe_load(data_box_repo_prometheus(env))
  config["scrape_configs"].find { |c| c["job_name"] == job }["static_configs"] = [{ "targets" => ["10.9.9.9:9100"] }]
  @data_box_live = config.to_yaml
end

Given("the live Prometheus config is the {string} repo config preceded by {string}") do |env, line|
  @data_box_live = "#{line}\n#{data_box_repo_prometheus(env)}"
end

Given("the live Prometheus config is {string}") do |text|
  @data_box_live = text
end

When("the data box Prometheus push is planned against the {string} repo config") do |env|
  @data_box_push = DataBoxExporters.prometheus_push_plan(live_text: @data_box_live, repo_text: data_box_repo_prometheus(env))
end

Then("the data box Prometheus push is {string}") do |status|
  expect(@data_box_push[:status]).to eq(status.to_sym), @data_box_push[:reason]
end

Then("the data box Prometheus push is {string} mentioning {string}") do |status, text|
  expect(@data_box_push[:status]).to eq(status.to_sym), @data_box_push[:reason]
  expect(@data_box_push[:reason]).to include(text)
end

# --- Drift guard: repo Prometheus targets vs the app's service URLs ----------------------------

Then("the {string} repo Prometheus config scrapes {string} on port {int} at the {word} host") do |env, job, port, var|
  # The .env file is what the app (and the rake task) use to find the data box
  line = Rails.root.join(".env.#{env}").read.lines.find { |l| l.start_with?("#{var}=") }
  expect(line).to be_present, ".env.#{env} has no #{var}"
  host = DataBoxExporters.host_of(line.split("=", 2).last)
  expect(DataBoxExporters.targets_for(data_box_repo_prometheus(env), job)).to include("#{host}:#{port}")
end

Then("the data box host of {string} is {string}") do |url, host|
  expect(DataBoxExporters.host_of(url)).to eq(host)
end

# --- Dashboard patch --------------------------------------------------------------------------

When("the data box dashboard patch is applied twice to the Rails Metrics dashboard") do
  # GrafanaProvisioner lives in a rake file; its top-level namespace call needs Rake's DSL
  unless defined?(GrafanaProvisioner)
    require "rake"
    load Rails.root.join("lib/tasks/grafana_provision.rake").to_s
  end
  board = JSON.parse(Rails.root.join("config/initializers/observability/graphana/in/rails.dashboard.json").read)
  # Patch helpers only touch the board, so no Grafana connection (initialize) is needed
  provisioner = GrafanaProvisioner.allocate
  2.times { provisioner.send(:add_data_box_panels!, board) }
  @dashboard_panels = board["panels"]
end

Then("the dashboard has the data box panels") do
  ["Data Box Memory by Service", "MySQL Memory by Area (top 8)"].each do |title|
    expect(@dashboard_panels.count { |p| p["title"] == title }).to eq(1), "expected exactly one #{title.inspect} panel"
  end
end

Then("the dashboard has no {string} panel") do |title|
  expect(@dashboard_panels.none? { |p| p["title"] == title }).to be(true)
end

When("the {string} service dashboard is built") do |uid|
  unless defined?(GrafanaProvisioner)
    require "rake"
    load Rails.root.join("lib/tasks/grafana_provision.rake").to_s
  end
  # Builders only assemble JSON, so no Grafana connection is needed
  build = GrafanaProvisioner::SERVICE_DASHBOARDS.fetch(uid)[:build]
  @service_board = GrafanaProvisioner.allocate.send(build, "test-ds-uid")
end

Then("the service dashboard is titled {string} with panels {string} and {string}") do |title, first, last|
  titles = @service_board["panels"].reject { |p| p["type"] == "row" }.pluck("title")
  expect(@service_board["title"]).to eq(title)
  expect(titles.first).to eq(first)
  expect(titles.last).to eq(last)
end

Then("every service dashboard panel has a unique id and the datasource uid") do
  ids = @service_board["panels"].pluck("id")
  expect(ids.uniq.size).to eq(ids.size)
  @service_board["panels"].reject { |p| p["type"] == "row" }.each do |p|
    expect(p.dig("datasource", "uid")).to eq("test-ds-uid"), "#{p['title']} has no fixed datasource"
  end
end

# The WAF in front of Grafana blocks the literal "})/" (see build_overview_dashboard), so a panel
# with it shows an error in the browser even though the PromQL is valid
Then("no service dashboard query contains {string}") do |sequence|
  @service_board["panels"].flat_map { |p| Array(p["targets"]) }.each do |t|
    expect(t["expr"]).not_to include(sequence)
  end
end
