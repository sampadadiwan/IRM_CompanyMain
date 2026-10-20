# frozen_string_literal: true

# Runs the support machine's Node tests (support_console/machine/test/) for one worked-example ID.
# Tests that need the local MySQL skip themselves when `rake support_console:local_setup` has not run.

When('the support machine tests matching {string} run') do |id|
  machine = Rails.root.join("support_console/machine")
  system("npm", "ci", "--no-audit", "--no-fund", chdir: machine.to_s, out: File::NULL) unless machine.join("node_modules").exist?
  @node_output, status = Open3.capture2e("node", "--test", "--test-name-pattern", id, *Dir[machine.join("test/*.test.js").to_s],
                                         chdir: machine.to_s)
  @node_passed = status.success?
end

Then('they pass') do
  expect(@node_passed).to be(true), @node_output
  expect(@node_output).to match(/^# pass [1-9]/)
end

# X27 — the archive support_console:publish_code uploads, built into a scratch folder.
When('the code archive is built from HEAD') do
  @archive_dir = Rails.root.join("tmp/support_console/archive-#{ENV.fetch('TEST_ENV_NUMBER', '')}-#{SecureRandom.hex(4)}")
  SupportConsoleCodeArchive.extract("HEAD", @archive_dir)
end

Then('the archive holds {string} and {string}') do |first, second|
  [first, second].each { |path| expect(@archive_dir.join(path)).to exist }
end

Then('the archive holds none of {string}') do |paths|
  present = paths.split(",").map(&:strip).select { |path| @archive_dir.join(path).exist? }
  expect(present).to be_empty, "the archive holds #{present.join(', ')}"
end

After { FileUtils.rm_rf(@archive_dir) if @archive_dir }
