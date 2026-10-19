# The must-have gate: a fund needs certain answers from the client before each step may run. They are the "M" questions
# in <client>_client_questions.md (section "M. Must-have before we go on", ids M1–M14), each with a status line:
#   *Status:* open | assumed | answered 2026-10-20
# M14 is the fund-ops review sign-off — set only by the reviewer ("answered <date> by <reviewer>"), never by the agent.
# A step runs only when every M item it needs is "answered".
#
# Override (onboarding.yml):  mode: check_data, check_data_approved_by: <name>, check_data_approved_on: <date>
#   lets the DATA steps run on assumptions — fund, commitments, drawdowns, distributions — so the client's data can be
#   imported and checked. It NEVER unlocks investor_access or go_live: those need every M item answered, and go_live
#   also needs a passing fund reconciliation (out/fund_recon.json from tools/fund/fund_recon.rb).
#
# Library: Onboarding::Gate.check!(workspace, :drawdowns)   (aborts with the list of unanswered items)
# CLI:     ruby gate.rb [--workspace DIR] [step …]           (no step: print every step's status)
require "yaml"
require "date"
require "json"

module Onboarding
  module Gate
    # What each step needs from the client (ids in the questions template's M section)
    STEPS = {
      fund: %w[M1 M2 M3 M4 M5],
      commitments: %w[M6],
      drawdowns: %w[M6 M7 M8 M9 M11],
      distributions: %w[M10 M11],
      investor_access: %w[M1 M2 M3 M4 M5 M6 M7 M8 M9 M10 M11 M12 M13 M14],
      go_live: %w[M1 M2 M3 M4 M5 M6 M7 M8 M9 M10 M11 M12 M13 M14]
    }.freeze
    # Steps the check-data override may unlock (importing and checking data only)
    OVERRIDABLE = %i[fund commitments drawdowns distributions].freeze
    # Import types → the step they belong to (api.rb upload)
    IMPORT_STEP = {
      "Fund" => :fund, "FundUnitSetting" => :fund, "Investor" => :commitments, "CapitalCommitment" => :commitments,
      "CapitalCall" => :drawdowns, "CapitalRemittance" => :drawdowns, "CapitalRemittancePayment" => :drawdowns,
      "CapitalDistribution" => :distributions, "CapitalDistributionPayment" => :distributions,
      "InvestorAccess" => :investor_access, "InvestorAdvisor" => :investor_access
    }.freeze

    module_function

    def config(workspace)
      path = File.join(workspace, "onboarding.yml")
      File.exist?(path) ? YAML.safe_load_file(path, permitted_classes: [Date]) : {}
    end

    # { "M1" => "answered 2026-10-20", "M2" => "assumed", … } from the questions file's M section
    def statuses(workspace)
      client = config(workspace)["client"] || File.basename(workspace).split("-").first
      path = File.join(workspace, "#{client}_client_questions.md")
      abort "✖ #{File.basename(path)} is missing — create it from client-questions-template.md (hard rule 8)" unless File.exist?(path)
      text = File.read(path)
      text.scan(/\*\*(M\d+)\.(.*?)(?=\*\*M\d+\.|\n## |\z)/m).to_h do |id, body|
        [id, body[/\*Status:\*\s*([^\n]+)/, 1].to_s.strip.downcase]
      end
    end

    # Go-live also needs proof the data ties: out/fund_recon.json (tools/fund/fund_recon.rb) with passed: true
    # → nil when it does, else the reason it does not
    def recon_blocker(workspace)
      path = File.join(workspace, "out", "fund_recon.json")
      return "no fund reconciliation yet (run tools/fund/fund_recon.rb)" unless File.exist?(path)

      r = JSON.parse(File.read(path))
      r["passed"] == true ? nil : "fund reconciliation failed (#{r['ok']}/#{r['checks']} on #{r['generated_at']})"
    end

    # → [allowed?, unanswered ids (plus any recon blocker), override_used?]
    def evaluate(workspace, step)
      needed = STEPS.fetch(step.to_sym) { abort "unknown step #{step} (#{STEPS.keys.join(', ')})" }
      st = statuses(workspace)
      unanswered = needed.reject { st[_1].to_s.start_with?("answered") }
      unanswered << recon_blocker(workspace) if step.to_sym == :go_live && recon_blocker(workspace)
      return [true, [], false] if unanswered.empty?

      cfg = config(workspace)
      override = cfg["mode"] == "check_data" && OVERRIDABLE.include?(step.to_sym)
      override &&= cfg["check_data_approved_by"].to_s != "" && cfg["check_data_approved_on"].to_s != ""
      [override, unanswered, override]
    end

    # Aborts unless the step may run; prints the CHECK-DATA banner when the override is what lets it through
    def check!(workspace, step)
      allowed, unanswered, override = evaluate(workspace, step)
      if override
        cfg = config(workspace)
        warn "⚠ CHECK-DATA MODE (approved by #{cfg['check_data_approved_by']} on #{cfg['check_data_approved_on']}): " \
             "step #{step} runs on assumptions for #{unanswered.join(' ')} — for importing and checking data only; " \
             "investor access and go-live stay blocked until these are answered."
      end
      return if allowed

      hint = OVERRIDABLE.include?(step.to_sym) ? " (or, to import and check data only: mode: check_data in onboarding.yml with approver + date)" : " — no override for this step"
      m_ids, other = unanswered.partition { _1.match?(/\AM\d+\z/) }
      reasons = [("the client has not answered #{m_ids.join(' ')} in the questions file's M section" if m_ids.any?), *other].compact.join("; ")
      abort "✖ gate #{step}: #{reasons}#{hint}"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  # Own --workspace handling (requiring api.rb here would load this file a second time through its require_relative)
  i = ARGV.index("--workspace")
  workspace = File.expand_path(i ? ARGV.slice!(i, 2).last : ENV.fetch("ONBOARDING_WORKSPACE", Dir.pwd))
  steps = ARGV.empty? ? Onboarding::Gate::STEPS.keys : ARGV.map(&:to_sym)
  st = Onboarding::Gate.statuses(workspace)
  puts "M items: " + Onboarding::Gate::STEPS[:go_live].map { "#{_1}=#{st[_1] || 'missing'}" }.join("  ")
  mode = Onboarding::Gate.config(workspace)["mode"] || "production"
  puts "mode: #{mode}"
  puts "fund recon: #{Onboarding::Gate.recon_blocker(workspace) || 'passed (' + JSON.parse(File.read(File.join(workspace, 'out', 'fund_recon.json'))).values_at('ok', 'checks', 'generated_at').then { |o, c, g| "#{o}/#{c}, #{g}" } + ')'}"
  failed = false
  steps.each do |s|
    allowed, unanswered, override = Onboarding::Gate.evaluate(workspace, s)
    failed ||= !allowed
    m_ids, other = unanswered.partition { _1.match?(/\AM\d+\z/) }
    why = [("needs #{m_ids.join(' ')}" if m_ids.any?), *other].compact.join("; ")
    puts format("  %-16s %s", s, allowed ? (override ? "✔ open via check-data override (assumed: #{m_ids.join(' ')})" : "✔ open") : "✖ blocked — #{why}")
  end
  exit(failed ? 1 : 0)
end
