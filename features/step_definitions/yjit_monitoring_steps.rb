# frozen_string_literal: true

# Steps for features/misc/yjit_monitoring.feature. The alert-rule steps ("I read the provisioned
# Grafana alert rules", "there should be an alert rule titled", "that rule should watch") are
# shared with clock_sync_monitoring_steps.rb.

# --yjit-mem-size default, in MiB (`ruby --help`)
YJIT_DEFAULT_MEM_LIMIT_MB = 128

When("I take a YJIT metrics snapshot") do
  @yjit_snapshot = YjitMetrics.snapshot
end

When("I take a YJIT metrics snapshot with config.yjit off") do
  # Only the expected gauge reads config.yjit; YJIT itself stays on for the rest of the run
  original = Rails.application.config.yjit
  Rails.application.config.yjit = false
  @yjit_snapshot = YjitMetrics.snapshot
ensure
  Rails.application.config.yjit = original
end

Then("the snapshot reports YJIT as running and expected") do
  # Tests run under YJIT: config/initializers/yjit_check.rb refuses to boot the test env without it
  expect(@yjit_snapshot).to include(enabled: 1, expected: 1)
end

Then("the snapshot reports YJIT's code and bookkeeping memory") do
  expect(@yjit_snapshot[:code_region_bytes]).to be_positive
  expect(@yjit_snapshot[:alloc_bytes]).to be_positive
end

Then("the snapshot reports YJIT as not expected") do
  expect(@yjit_snapshot[:expected]).to eq(0)
end

Then("that rule's threshold should be below YJIT's 128 MB memory limit") do
  expect(@alert_rule["threshold_gt"]).to be < YJIT_DEFAULT_MEM_LIMIT_MB
end

When("the YJIT dashboard patch is applied twice to the Rails Metrics dashboard") do
  # GrafanaProvisioner lives in a rake file; its top-level namespace call needs Rake's DSL
  unless defined?(GrafanaProvisioner)
    require "rake"
    load Rails.root.join("lib/tasks/grafana_provision.rake").to_s
  end
  board = JSON.parse(Rails.root.join("config/initializers/observability/graphana/in/rails.dashboard.json").read)
  # Patch helpers only touch the board, so no Grafana connection (initialize) is needed
  provisioner = GrafanaProvisioner.allocate
  2.times { provisioner.send(:add_yjit_panels!, board) }
  @dashboard_panels = board["panels"]
end

Then("the dashboard has one {string} row") do |title|
  rows = @dashboard_panels.select { |p| p["type"] == "row" && p["title"] == title }
  expect(rows.size).to eq(1)
end

Then("the dashboard has panels {string}, {string}, {string} and {string}") do |*titles|
  titles.each do |title|
    expect(@dashboard_panels.count { |p| p["title"] == title }).to eq(1), "expected exactly one #{title.inspect} panel"
  end
end
