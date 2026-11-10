# frozen_string_literal: true

require "json"
require "time"

# Post-deploy steps: the manual things a deployer must do after a release reaches an environment
# (switch a flag on, run a rake task with EXECUTE=1, message some users, run a QA checklist).
#
# Each change that needs any writes one file, post_deploy_steps/<change-name>.md, with a section per environment
# (see post_deploy_steps/README.md for the format). After every deploy, Capistrano's post_deploy:checklist
# (lib/capistrano/tasks/post_deploy.rake) works out which of the deployed release's steps this environment has not
# yet done, prints them one by one and makes the deployer answer each: "done", or "skip <reason>". Answers are
# appended to a log on the environment's primary server; a skipped or unanswered step is shown again on the next
# deploy to that environment, so nothing is lost when a release is skipped or a deploy fails half-way.
#
# Plain Ruby on purpose: Capistrano loads it on the deployer's machine, outside Rails.
module PostDeploySteps
  # The environments that are deployed (config/deploy/<name>.rb). staging_us is not a live environment.
  ENVS = %w[staging_in production_in production_us].freeze

  # Section headings a file may use, and the environments each one applies to. "production" lists a step once for
  # both production regions; each region still answers it separately (they are independent environments).
  SECTIONS = {
    "all" => ENVS,
    "production" => %w[production_in production_us],
    "staging_in" => %w[staging_in],
    "production_in" => %w[production_in],
    "production_us" => %w[production_us]
  }.freeze

  STEP_ID = /\A[a-z0-9][a-z0-9-]*\z/
  # A file with nothing to do says so, with a reason: "None — <reason>"
  NONE_LINE = /\ANone\s+[—-]+\s+\S/
  README = "README.md"

  # One step: the file it came from (the change name), its id within the file, its title, the instructions below
  # the heading, and the environments it applies to
  Step = Struct.new(:file, :id, :title, :body, :envs) do
    # Unique across all files; the key the log records
    def key
      "#{file}##{id}"
    end
  end

  # A parsed file: its steps and any format errors (empty when the file is well-formed)
  Parsed = Struct.new(:name, :steps, :errors, :none)

  module_function

  # Parses one file's text. `name` is the file name without ".md" (the change name).
  # @return [Parsed]
  def parse(name, text)
    steps = []
    errors = []
    none = false
    section = nil
    current = nil
    title_seen = false

    text.each_line do |raw|
      line = raw.chomp
      case line
      when /\A# (?!#)/
        # The file's title
        title_seen = true
      when /\A## (?!#)(.*)\z/
        # A new environment section; an unknown name is an error (a typo would silently skip an env)
        current = nil
        section = Regexp.last_match(1).strip
        errors << "#{name}: unknown section \"## #{section}\" (use one of: #{SECTIONS.keys.join(', ')})" unless SECTIONS.key?(section)
      when /\A### (?!#)(.*)\z/
        heading = Regexp.last_match(1).strip
        id, title = heading.split(/\s+[—-]+\s+/, 2)
        if section.nil?
          errors << "#{name}: step \"#{heading}\" is not under an environment section (## all, ## production_in, …)"
        elsif !id.to_s.match?(STEP_ID) || title.to_s.strip.empty?
          errors << "#{name}: step heading must read \"### <id> — <title>\" with a lower-case id, got \"### #{heading}\""
        end
        current = Step.new(name, id.to_s, title.to_s.strip, +"", SECTIONS.fetch(section, []))
        steps << current
      else
        # A "None — reason" line before any section marks a file with nothing to do
        none = true if section.nil? && line.strip.match?(NONE_LINE)
        current.body << line << "\n" if current
      end
    end

    steps.each { |step| step.body = step.body.strip }
    duplicate_ids = steps.map(&:id).tally.select { |_, count| count > 1 }.keys
    duplicate_ids.each { |id| errors << "#{name}: step id \"#{id}\" is used more than once" }
    errors << "#{name}: the file needs a \"# Post-deploy steps — …\" title" unless title_seen
    errors << "#{name}: no steps — add steps, or a line \"None — <reason>\"" if steps.empty? && !none
    errors << "#{name}: has steps and a \"None —\" line; keep one" if steps.any? && none
    Parsed.new(name, steps, errors, none)
  end

  # Parses every file in a directory (README.md excluded). `files` maps file name => text, so the same code reads a
  # local checkout (lint, tests) or files fetched from a server (Capistrano).
  # @return [Array<Parsed>]
  def parse_all(files)
    files.reject { |file_name, _| file_name == README || !file_name.end_with?(".md") }
         .sort_by(&:first)
         .map { |file_name, text| parse(File.basename(file_name, ".md"), text) }
  end

  # Reads a local directory into the file name => text map parse_all takes
  def read_dir(dir)
    Dir.glob(File.join(dir, "*.md")).to_h { |path| [File.basename(path), File.read(path)] }
  end

  # Every format error across the files (empty means all well-formed)
  def lint(files)
    parse_all(files).flat_map(&:errors)
  end

  # The log's lines (JSON, one per answer) as hashes; a malformed line is ignored rather than stopping a deploy
  def parse_log(text)
    text.to_s.each_line.filter_map do |line|
      JSON.parse(line)
    rescue JSON::ParserError
      nil
    end
  end

  # The steps this environment still has to do: every step in the deployed files that applies to `env`, minus the
  # ones the log already records as done for `env`. A skipped step stays pending, so it is asked again next time.
  def pending(files, env, log_text)
    done = parse_log(log_text).select { |entry| entry["env"] == env && entry["answer"] == "done" }.to_set { |entry| entry["step"] }
    # Plain Ruby (no ActiveSupport in Capistrano), so no #exclude?
    parse_all(files).flat_map(&:steps).select { |step| step.envs.include?(env) && !done.include?(step.key) } # rubocop:disable Rails/NegateInclude
  end

  # One log line for an answer
  def log_line(step, env:, answer:, reason:, by:, ref:, revision:, at: Time.now.utc)
    JSON.generate({ "step" => step.key, "env" => env, "answer" => answer, "reason" => reason, "by" => by,
                    "at" => at.iso8601, "ref" => ref, "revision" => revision })
  end

  # Asks the deployer about each pending step and yields every answer as it is given (so an interrupted session
  # keeps what was already answered). `input` / `output` are IO-like, so tests drive it without a terminal.
  # @yieldparam step [Step] @yieldparam answer ["done", "skip"] @yieldparam reason [String, nil]
  # @return [Hash] counts of "done" and "skip" answers
  def ask_each(steps, env:, input:, output:)
    counts = { "done" => 0, "skip" => 0 }
    steps.each_with_index do |step, index|
      print_step(step, index, steps.size, env, output)
      answer, reason = read_answer(input, output)
      counts[answer] += 1
      yield step, answer, reason
    end
    counts
  end

  # The header and instructions of one step
  def print_step(step, index, total, env, output)
    output.puts
    output.puts "──── Post-deploy step #{index + 1} of #{total} · #{env} · #{step.key} ────"
    output.puts step.title
    output.puts
    output.puts step.body unless step.body.empty?
    output.puts
  end

  # Reads until the deployer types "done" or "skip <reason>"; anything else asks again.
  # @return [Array(String, String|nil)]
  def read_answer(input, output)
    loop do
      output.print 'Type "done" once it is done, or "skip <reason>": '
      line = input.gets
      # End of input (Ctrl-D, or a closed pipe): stop rather than loop forever; answered steps are already logged
      raise Interrupt, "post-deploy checklist stopped before every step was answered" if line.nil?

      text = line.strip
      return ["done", nil] if text.casecmp?("done")

      if (match = text.match(/\Askip\s+(.+)\z/i))
        return ["skip", match[1].strip]
      end

      output.puts text.match?(/\Askip\z/i) ? "A skip needs a reason, e.g. \"skip waiting for the firm admin\"." : "Not understood."
    end
  end

  # The message when steps are pending but nobody can answer (no terminal, e.g. a CI deploy)
  def unanswered_message(steps, env, stage)
    lines = ["#{steps.size} post-deploy step(s) for #{env} are not answered:"]
    steps.each { |step| lines << "  - #{step.key}: #{step.title}" }
    lines << "The release is deployed. Run the steps, then answer them with: bundle exec cap #{stage} post_deploy:checklist"
    lines.join("\n")
  end
end
