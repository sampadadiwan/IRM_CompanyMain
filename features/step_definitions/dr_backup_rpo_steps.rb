# frozen_string_literal: true

# Steps for features/misc/dr_backup_rpo.feature. Pure: crontab text and byte counts in memory.

Given("a live backup crontab:") do |text|
  @dr_crontab = "#{text}\n"
end

When("it is moved to a 30-minute cadence") do
  @dr_cadence = Dr::BackupSchedule.thirty_minute_cadence(@dr_crontab)
end

Then("the cadence change is {string}") do |status|
  expect(@dr_cadence[:status]).to eq(status.to_sym)
end

Then("the incremental line reads {string}") do |line|
  expect(@dr_cadence[:text].lines.map(&:chomp)).to include(line)
end

Then("every other line is unchanged") do
  before = @dr_crontab.lines.reject { |l| l.include?(" incr") }
  after = @dr_cadence[:text].lines.reject { |l| l.include?(" incr") }
  expect(after).to eq(before)
end

When("the cadence task is asked for {string}") do |env|
  @dr_allowed = Dr::BackupSchedule.cadence_env_allowed?(env)
end

Then("it is {string}") do |verdict|
  expect(@dr_allowed).to eq(verdict == "allowed")
end

When("a full of {int} bytes is size-checked against {int}, {int} and {int}") do |latest, a, b, c|
  @dr_grade = Dr::BackupSchedule.grade_full_size(name: "2026-11-07_230001-full", latest: latest, previous: [a, b, c])
end

When("a full of {int} bytes is size-checked against {int} and {int}") do |latest, a, b|
  @dr_grade = Dr::BackupSchedule.grade_full_size(name: "2026-11-07_230001-full", latest: latest, previous: [a, b])
end

Then("the size grade is {string}") do |status|
  expect(@dr_grade.status).to eq(status.to_sym)
end

Then("the size grade is {string} mentioning {string}") do |status, text|
  expect(@dr_grade.status).to eq(status.to_sym)
  expect(@dr_grade.detail).to include(text)
end
