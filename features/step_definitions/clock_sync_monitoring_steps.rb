# frozen_string_literal: true

# Steps for features/misc/clock_sync_monitoring.feature - a configuration guard over the
# provisioned Grafana rules and the Capistrano clock check, in the style of
# notification_attachment_size_steps.rb. It reads the files; it does not talk to Grafana.

GRAFANA_PROVISION_PATH = Rails.root.join("config/initializers/observability/grafana_provision.yml")
DEPLOY_RB_PATH = Rails.root.join("config/deploy.rb")

When("I read the provisioned Grafana alert rules") do
  @alert_rules = YAML.safe_load_file(GRAFANA_PROVISION_PATH, aliases: true).fetch("alert_rules")
end

Then("there should be an alert rule titled {string}") do |title|
  @alert_rule = @alert_rules.find { |r| r["title"] == title }
  expect(@alert_rule).to be_present,
                         "no alert rule titled #{title.inspect}; found: #{@alert_rules.map { |r| r['title'] }}"
end

Then("that rule should watch {string}") do |metric|
  expect(@alert_rule["expr"]).to include(metric)
end

# 30 seconds against a 5-minute credential: an order of magnitude of headroom, so drift is
# reported long before it starts rejecting switches.
Then("that rule's threshold should be below the hand-off credential lifetime") do
  expect(@alert_rule["threshold_gt"]).to be < CrossSiteLink::LIFETIME.to_i
end

Then("every rule should use only the {string} comparator") do |comparator|
  used = @alert_rules.flat_map { |r| r.keys.grep(/\Athreshold/) }.uniq
  expect(used).to eq([comparator]),
                  "lib/tasks/grafana_provision.rake only builds #{comparator}; found #{used.inspect}"
end

When("I read the deploy configuration") do
  @deploy_rb = File.read(DEPLOY_RB_PATH)
end

Then("it should define a {string} task") do |name|
  expect(@deploy_rb).to include("task :#{name} do")
  @deploy_task = @deploy_rb[/task :#{name} do.*?\n  end\n/m]
  expect(@deploy_task).to be_present
end

Then("that task should run on the app role") do
  expect(@deploy_task).to include("on roles(:app)")
end

Then("that task should check both NTP synchronisation and the time daemon") do
  expect(@deploy_task).to include("NTPSynchronized")
  expect(@deploy_task).to match(/chrony|systemd-timesyncd/)
end
