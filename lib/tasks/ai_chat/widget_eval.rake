# frozen_string_literal: true

# Checks that the model picks the right optional answer widgets (AiChatAnswerLayout::WIDGETS) for typical
# questions — Verdict, Checks and What to do only when called for, none on simple list/count questions.
#
# The shared prompt alone (no tools, no data — which sections the model chooses, not the figures):
#   ENTITY_ID=23 bundle exec rake ai_chat:widget_eval
#
# A real assistant — its own prompt, tools and data — with questions from
# config/ai_chat/widget_eval/<assistant>.yml (e.g. portfolio_company.yml):
#   ASSISTANT=PortfolioCompanyAssistant PORTFOLIO_COMPANY_ID=258 USER_ID=103 bundle exec rake ai_chat:widget_eval
#   (also FUND_ID for SpecificFundAssistant, CAPITAL_COMMITMENT_ID for CapitalCommitmentAssistant)
#
# REPEAT=3 asks each question three times (answers vary between runs): it reports how often each widget was
# used, and a question passes when most of its answers are right. MODEL=… overrides the model.
# The shared-prompt run saves nothing; an assistant run answers in a throwaway chat that is deleted afterwards. Run it after changing AiChatAnswerLayout or an assistant's prompt.
module AiChatWidgetEval
  WIDGETS = %w[verdict checks what_to_do].freeze
  QUESTIONS_DIR = Rails.root.join("config/ai_chat/widget_eval")
  # ASSISTANT → [the owner it needs (env var, model, constructor keyword), question file]
  ASSISTANTS = {
    "PortfolioCompanyAssistant" => [%w[PORTFOLIO_COMPANY_ID Investor portfolio_company], "portfolio_company"],
    "SpecificFundAssistant" => [%w[FUND_ID Fund fund], "specific_fund"],
    "CapitalCommitmentAssistant" => [%w[CAPITAL_COMMITMENT_ID CapitalCommitment capital_commitment], "capital_commitment"],
    "FundAssistant" => [nil, "fund"],
    "PortfolioAssistant" => [nil, "portfolio"]
  }.freeze

  module_function

  # Asks every case's question `repeat` times (via the block, which returns the answer's markdown) and
  # prints how often each widget was used against `expect` / `forbid`, then each widget's overall use.
  #
  # @param cases [Array<Hash>] question, expect, forbid
  # @param repeat [Integer] answers per question; a question passes when most of them are right
  def evaluate(cases, repeat: 1)
    samples = []
    results = cases.map do |test|
      expect = Array(test["expect"])
      forbid = Array(test["forbid"])
      # The widgets each answer used, one entry per answer.
      answers = Array.new(repeat) { AiChatAnswerLayout.sections_in(yield(test["question"])) & WIDGETS }
      samples.concat(answers)
      right = answers.count { |used| (expect - used).empty? && !forbid.intersect?(used) }
      ok = right * 2 > repeat
      puts "#{ok ? '✓' : '✗'} #{test['question']}#{"  (#{right}/#{repeat} right)" if repeat > 1}"
      puts "    #{usage_line(answers, repeat)}"
      puts "    expected: #{expect.join(', ').presence || 'none'}  should not use: #{forbid.join(', ').presence || 'none'}" unless ok
      ok
    end
    puts "\n#{results.count(true)}/#{results.size} questions picked the right widgets" \
         "#{" (most of #{repeat} answers each)" if repeat > 1}"
    WIDGETS.each { |w| puts "  #{w}: used in #{samples.count { |used| used.include?(w) }}/#{samples.size} answers" }
  end

  # @return [String] e.g. "used: checks" (one answer) or "used: checks 1/3, verdict 3/3" (several)
  def usage_line(answers, repeat)
    counts = WIDGETS.filter_map do |widget|
      n = answers.count { |used| used.include?(widget) }
      next if n.zero?

      repeat > 1 ? "#{widget} #{n}/#{repeat}" : widget
    end
    "used: #{counts.join(', ').presence || 'none'}"
  end

  # @return [Array<Hash>] the question file's cases, falling back to the shared ones
  def cases_for(file, owner_name: nil)
    path = QUESTIONS_DIR.join("#{file}.yml")
    path = QUESTIONS_DIR.join("generic.yml") unless path.exist?
    puts "Questions: #{path.relative_path_from(Rails.root)}\n\n"
    YAML.load_file(path).map { |c| c.merge("question" => c["question"].gsub("{company}", owner_name.to_s)) }
  end
end

namespace :ai_chat do
  desc "Check which optional answer widgets the model picks (ENTITY_ID=…, or ASSISTANT=… with its record and USER_ID=…)"
  task widget_eval: :environment do
    repeat = [ENV.fetch("REPEAT", "1").to_i, 1].max
    if (name = ENV["ASSISTANT"].presence)
      owner_spec, file = AiChatWidgetEval::ASSISTANTS.fetch(name) { abort "ASSISTANT must be one of #{AiChatWidgetEval::ASSISTANTS.keys.join(', ')}" }
      user = User.find(ENV.fetch("USER_ID") { abort "Set USER_ID (the user the assistant answers for)" })
      env_var, owner_class, keyword = owner_spec
      owner = owner_class&.constantize&.find(ENV.fetch(env_var) { abort "Set #{env_var}" })
      puts "#{name} for #{owner || user} as #{user.full_name}"

      AiChatWidgetEval.evaluate(AiChatWidgetEval.cases_for(file, owner_name: owner), repeat:) do |question|
        # A throwaway chat per question, so answers do not build on each other; deleted afterwards.
        chat = Chat.create!(user:, entity_id: user.entity_id, assistant_type: name, owner: owner || user,
                            name: "widget eval", model: ENV["MODEL"].presence || PortfolioCompanyAssistant::AI_MODEL)
        begin
          assistant = name.constantize.new(user:, chat:, **(keyword ? { keyword.to_sym => owner } : {}))
          assistant.run(question).content
        ensure
          chat.destroy
        end
      end
    else
      entity = Entity.find(ENV.fetch("ENTITY_ID") { abort "Set ENTITY_ID (its LLM key and default model are used), or ASSISTANT=…" })
      preamble = "You are a CapHive assistant answering a fund manager's question. You have no tools and no data " \
                 "in this conversation: where figures are needed, use plausible illustrative ones."
      AiChatWidgetEval.evaluate(AiChatWidgetEval.cases_for("generic"), repeat:) do |question|
        chat = LlmService.ruby_llm_chat(entity:, model: ENV.fetch("MODEL", nil))
        chat.with_instructions("#{preamble}\n\n#{AiChatAnswerLayout.instructions}")
        chat.ask(question).content
      end
    end
  end
end
