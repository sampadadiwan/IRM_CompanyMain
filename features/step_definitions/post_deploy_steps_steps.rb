# frozen_string_literal: true

# Steps for features/core/post_deploy_steps.feature (lib/post_deploy_steps.rb). The library is plain Ruby, so these
# drive it directly: files are a name => text map, the log is a String, and the deployer's answers come from a
# StringIO — no SSH, no terminal.
require Rails.root.join("lib/post_deploy_steps").to_s
require "stringio"

module PostDeployStepsWorld
  def pds_files
    @pds_files ||= {}
  end

  def pds_log
    @pds_log ||= +""
  end
end
World(PostDeployStepsWorld)

Given("a post-deploy steps file {string} with:") do |name, text|
  # Outline examples write newlines as \n inside one table cell
  pds_files["#{name}.md"] = text.gsub("\\n", "\n")
end

Then("the open post-deploy steps for {string} are {string}") do |env, keys|
  expected = keys.split(",").map(&:strip).reject(&:empty?)
  expect(PostDeploySteps.pending(pds_files, env, pds_log).map(&:key)).to eq(expected)
end

Then("the post-deploy step {string} has the instructions {string}") do |key, text|
  step = PostDeploySteps.parse_all(pds_files).flat_map(&:steps).find { |s| s.key == key }
  expect(step.body).to include(text)
end

When("the deployer answers the {string} checklist with:") do |env, table|
  input = StringIO.new(table.hashes.map { |row| "#{row['answer']}\n" }.join)
  @pds_output = StringIO.new
  steps = PostDeploySteps.pending(pds_files, env, pds_log)
  begin
    PostDeploySteps.ask_each(steps, env:, input:, output: @pds_output) do |step, answer, reason|
      # As the Capistrano task does: append each answer as it is given
      pds_log << PostDeploySteps.log_line(step, env:, answer:, reason:, by: "Test Deployer", ref: "V9.9.9", revision: "abc123") << "\n"
    end
    @pds_stopped = false
  rescue Interrupt
    @pds_stopped = true
  end
end

Then("the post-deploy log records {string} as {string} for {string}") do |key, answer, env|
  entry = PostDeploySteps.parse_log(pds_log).rfind { |e| e["step"] == key && e["env"] == env }
  expect(entry).to include("answer" => answer, "by" => "Test Deployer", "ref" => "V9.9.9", "revision" => "abc123")
end

Then("the post-deploy log records {string} as {string} for {string} with the reason {string}") do |key, answer, env, reason|
  entry = PostDeploySteps.parse_log(pds_log).rfind { |e| e["step"] == key && e["env"] == env }
  expect(entry).to include("answer" => answer, "reason" => reason)
end

Then("the checklist said {string}") do |text|
  expect(@pds_output.string).to include(text)
end

Then("the checklist stopped before every step was answered") do
  expect(@pds_stopped).to be(true)
end

Then("the post-deploy steps files are well-formed") do
  expect(PostDeploySteps.lint(pds_files)).to eq([])
end

Then("linting the post-deploy steps reports {string}") do |text|
  errors = PostDeploySteps.lint(pds_files)
  expect(errors.join("\n")).to include(text)
end

Then("the unanswered message for {string} lists {string}") do |env, text|
  message = PostDeploySteps.unanswered_message(PostDeploySteps.pending(pds_files, env, pds_log), env, env)
  expect(message).to include(text)
end

Then("the unanswered message for {string} says {string}") do |env, text|
  message = PostDeploySteps.unanswered_message(PostDeploySteps.pending(pds_files, env, pds_log), env, env)
  expect(message).to include(text)
end

# PD1 — the real folder
Then("every file in post_deploy_steps is well-formed") do
  files = PostDeploySteps.read_dir(Rails.root.join("post_deploy_steps").to_s)
  expect(files.keys).to include("owasp-top10-2026-11.md")
  expect(PostDeploySteps.lint(files)).to eq([]), "fix these post_deploy_steps files:\n#{PostDeploySteps.lint(files).join("\n")}"
end

# PD2 — openspec/changes/archive/YYYY-MM-DD-<change>/ needs post_deploy_steps/<change>.md once the rule applies
Then("every OpenSpec change archived since {string} has a post-deploy steps file") do |since|
  archived = Dir.glob(Rails.root.join("openspec/changes/archive/*").to_s).filter_map do |dir|
    match = File.basename(dir).match(/\A(\d{4}-\d{2}-\d{2})-(.+)\z/)
    match[2] if match && match[1] >= since
  end
  missing = archived.reject { |change| Rails.root.join("post_deploy_steps", "#{change}.md").exist? }
  expect(missing).to be_empty, "add post_deploy_steps/<change>.md (steps, or \"None — <reason>\") for: #{missing.join(', ')}"
end
