# frozen_string_literal: true

# Post-deploy steps checklist (post_deploy_steps/README.md, lib/post_deploy_steps.rb).
#
# After every deploy (deploy:finished) this prints the deployed release's steps that this environment has not yet
# done, and makes the deployer answer each one: "done" or "skip <reason>". Answers are appended to
# shared/post_deploy_log.jsonl on the environment's primary server, so the record lives with the environment:
# another person deploying the next release sees what is still open. A skipped step is asked again next deploy.
#
#   bundle exec cap production_in post_deploy:status      # list what is still open, ask nothing
#   bundle exec cap production_in post_deploy:checklist   # answer the open steps (runs after every deploy)
#
# Without a terminal (e.g. a CI deploy) the checklist prints the open steps and fails, so the deploy is reported as
# not finished; the release itself is already live.
require "shellwords"
require_relative "../../post_deploy_steps"

namespace :post_deploy do
  # production_in / production_us / staging_in, from the stage file's rails_env + env_variant
  # (stage files override :stage itself to :production / :staging)
  def post_deploy_env
    "#{fetch(:rails_env)}_#{fetch(:env_variant)}"
  end

  def post_deploy_log_path
    shared_path.join("post_deploy_log.jsonl")
  end

  # The deployed release's step files and this environment's log, read from the primary server
  # @return [Array(Hash, String, String)] files (name => text), log text, deployed revision
  def post_deploy_fetch
    files = {}
    log = +""
    revision = nil
    on roles(:primary) do
      dir = current_path.join("post_deploy_steps")
      if test("[ -d #{dir} ]")
        capture(:ls, "-1", dir).to_s.split("\n").each do |name|
          next unless name.end_with?(".md")

          files[name] = capture(:cat, dir.join(name)).to_s
        end
      end
      log = capture(:cat, post_deploy_log_path).to_s if test("[ -f #{post_deploy_log_path} ]")
      revision = capture(:cat, current_path.join("REVISION")).to_s.strip if test("[ -f #{current_path.join('REVISION')} ]")
    end
    [files, log, revision]
  end

  # Who is deploying: the local git name, falling back to the shell user
  def post_deploy_deployer
    name = `git config user.name 2>/dev/null`.strip
    name.empty? ? ENV.fetch("USER", "unknown") : name
  end

  desc "List this environment's post-deploy steps that are not done yet"
  task :status do
    env = post_deploy_env
    files, log, = post_deploy_fetch
    steps = PostDeploySteps.pending(files, env, log)
    if steps.empty?
      puts "No open post-deploy steps for #{env}."
    else
      puts "Open post-deploy steps for #{env}:"
      steps.each { |step| puts "  - #{step.key}: #{step.title}" }
    end
  end

  desc "Answer each of this environment's open post-deploy steps (done / skip <reason>)"
  task :checklist do
    env = post_deploy_env
    files, log, revision = post_deploy_fetch
    # A malformed file must not hide a step: report it, and still ask the steps that did parse
    PostDeploySteps.lint(files).each { |error| warn "post_deploy_steps: #{error}" }
    steps = PostDeploySteps.pending(files, env, log)

    if steps.empty?
      puts "Post-deploy steps: nothing open for #{env}."
      next
    end

    # Nobody to answer: list the steps and fail, so the deploy does not report a clean finish
    unless $stdin.tty?
      # The stage file is named after the environment (config/deploy/production_in.rb), so env is the cap stage
      raise PostDeploySteps.unanswered_message(steps, env, env)
    end

    puts
    puts "#{steps.size} post-deploy step(s) to run on #{env}. Run each one now, then answer it."
    by = post_deploy_deployer
    ref = fetch(:branch)
    log_path = post_deploy_log_path
    counts = PostDeploySteps.ask_each(steps, env:, input: $stdin, output: $stdout) do |step, answer, reason|
      line = PostDeploySteps.log_line(step, env:, answer:, reason:, by:, ref:, revision:)
      # Appended one answer at a time, so stopping half-way keeps what was answered
      on(roles(:primary)) { execute "echo #{Shellwords.escape(line)} >> #{log_path}" }
    end
    puts
    puts "Post-deploy steps for #{env}: #{counts['done']} done, #{counts['skip']} skipped " \
         "(skipped steps are asked again on the next deploy)."
  end
end

# Hooked in config/deploy.rb (after deploy:ensure_permissions), which loads after this file.
