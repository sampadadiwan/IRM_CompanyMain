# frozen_string_literal: true

# Steps for features/misc/dr_backup_schedule.feature. Everything here is pure: the crontab text,
# grades and Packer recipe are read or built in memory - nothing talks to a DB server or AWS.

PACKER_DB_RECIPE_PATH = Rails.root.join("config/deploy/templates/packer/db_redis_es.ami.pkr.hcl")

Given("a DB server crontab:") do |text|
  @dr_crontab = text
end

When("the old backup jobs are stripped from that crontab") do
  @dr_split = Dr::BackupSchedule.split_crontab(@dr_crontab)
end

Then("{int} crontab lines are kept") do |count|
  expect(@dr_split[:kept].size).to eq(count)
end

Then("{int} old backup jobs are removed") do |count|
  expect(@dr_split[:removed].size).to eq(count)
end

Then("no kept crontab line runs a backup script") do
  expect(@dr_split[:kept].grep(Dr::BackupSchedule::OLD_JOB_PATTERN)).to be_empty
end

When("a DR primary's backups are graded with the schedule {string} and old jobs {string}") do |schedule, old_jobs|
  # "present" old jobs stand in for the cloned staging line seen on 2026-11-08
  jobs = old_jobs == "present" ? ["0 0-22 * * * /home/ubuntu/backup_db.sh incr"] : []
  @dr_grade = Dr::BackupSchedule.grade_primary(schedule: schedule == "present", old_jobs: jobs)
end

When("a DR replica's backups are graded with old jobs {string}") do |old_jobs|
  jobs = old_jobs == "present" ? ["0 0-22 * * * /home/ubuntu/backup_db.sh incr"] : []
  @dr_grade = Dr::BackupSchedule.grade_replica(old_jobs: jobs)
end

When("a DR primary's armed marker is graded as {string}") do |armed|
  @dr_grade = Dr::BackupSchedule.grade_armed(armed == "present")
end

Then("the backup grade is {string}") do |status|
  expect(@dr_grade.status).to eq(status.to_sym)
end

Then("the backup grade is {string} mentioning {string}") do |status, text|
  expect(@dr_grade.status).to eq(status.to_sym)
  expect(@dr_grade.detail).to include(text)
end

When("I read the backup schedule and log rotation baked by the Packer recipe") do
  recipe = File.read(PACKER_DB_RECIPE_PATH)
  # Each is one `printf '%s\n' '<line>' '<line>' ... | sudo tee <path>` provisioner line; the
  # single-quoted tokens after the '%s\\n' format are the file's lines.
  baked_lines = lambda do |path|
    line = recipe.lines.find { |l| l.include?("printf") && l.include?("sudo tee #{path}") }
    expect(line).not_to be_nil, "no printf … | sudo tee #{path} line in #{PACKER_DB_RECIPE_PATH}"
    line.scan(/'([^']*)'/).flatten.drop(1)
  end
  @baked_cron = baked_lines.call(Dr::BackupSchedule::CRON_PATH)
  @baked_logrotate = baked_lines.call(Dr::BackupSchedule::LOGROTATE_PATH)
end

Then("they match the schedule and log rotation a DR restore installs") do
  expect(@baked_cron).to eq(Dr::BackupSchedule::CRON_LINES)
  expect(@baked_logrotate).to eq(Dr::BackupSchedule::LOGROTATE_LINES)
end

When("the backup script line {string} is classified") do |line|
  @dr_script_kind = Dr::BackupSchedule.baked_script?(line) ? "baked" : "generated"
end

Then("the backup script is classified as {string}") do |kind|
  expect(@dr_script_kind).to eq(kind)
end

When("a DR drill primary's armed marker is graded as {string}") do |armed|
  @dr_grade = Dr::BackupSchedule.grade_armed(armed == "present", drill: true)
end

When("the drill flag is read from DR_DRILL {string}") do |value|
  # A plain hash stands in for ENV, so the scenario never leaks a flag into the test process
  @dr_drill = Dr::BackupSchedule.drill?(value.empty? ? {} : { "DR_DRILL" => value })
end

Then("the run is treated as a drill: {string}") do |drill|
  expect(@dr_drill).to eq(drill == "yes")
end
