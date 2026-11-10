# frozen_string_literal: true

# Steps for features/misc/mysql_overview_dashboard.feature. Pure: the saved board JSON, patched in
# memory by GrafanaProvisioner#fix_mysql_overview_replication! - no Grafana connection.

When("the MySQL Overview replication patch is applied twice to the {string} board") do |region|
  # GrafanaProvisioner lives in a rake file; its top-level namespace call needs Rake's DSL
  unless defined?(GrafanaProvisioner)
    require "rake"
    load Rails.root.join("lib/tasks/grafana_provision.rake").to_s
  end
  saved = JSON.parse(Rails.root.join("config/initializers/observability/graphana/#{region}/mysql.dashboard.json").read)
  # Provisioning saves the bare board; a raw API export wraps it in "dashboard"
  @mysql_overview_before = saved["dashboard"] || saved
  board = @mysql_overview_before.deep_dup
  # Patch helpers only touch the board, so no Grafana connection (initialize) is needed
  provisioner = GrafanaProvisioner.allocate
  2.times { provisioner.send(:fix_mysql_overview_replication!, board) }
  @mysql_overview = board
end

Then("the {string} panel's {string} query reads both {string} and {string}") do |title, ref, new_name, old_name|
  panel = @mysql_overview["panels"].find { |p| p["title"] == title }
  expect(panel).to be_present, "no #{title.inspect} panel"
  expr = panel["targets"].find { |t| t["refId"] == ref }["expr"]
  expect(expr).to include("mysql_slave_status_#{new_name}{")
  expect(expr).to include("mysql_slave_status_#{old_name}{")
  # One "or" per metric pair - a second run must not stack another
  expect(expr.scan(" or ").size).to eq(1)
end

Then("no MySQL Overview query reads {string}") do |metric|
  exprs = @mysql_overview["panels"].flat_map { |p| Array(p["targets"]).pluck("expr") }.compact
  expect(exprs.grep(/#{Regexp.escape(metric)}\{/)).to be_empty
end

Then("the MySQL Overview panels other than replication are unchanged") do
  replication = GrafanaProvisioner::MYSQL_OVERVIEW_REPLICATION.keys
  untouched = ->(board) { board["panels"].reject { |p| replication.include?(p["title"]) } }
  expect(untouched.call(@mysql_overview)).to eq(untouched.call(@mysql_overview_before))
end
