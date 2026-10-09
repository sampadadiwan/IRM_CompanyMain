# Drafts a fund's mapping from its uploaded statements (card ② of the design): reads the file,
# lists the fund's entries, asks the AI, validates the answer and tags each line New / Changed / Same.
# Mapping only — no figures are compared. One AI call per upload / Retry, outside any transaction; any
# failure is stored on the suggestion with Retry offered, and the uploader gets a toast.
# Worked examples H11, E27, X12, X18 — openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementMappingSuggestJob < ApplicationJob
  queue_as :default

  def perform(suggestion_id)
    suggestion = FinancialStatementMappingSuggestion.find(suggestion_id)
    # A second enqueue (double click on Retry) finds it already done
    return unless suggestion.status == "processing"

    fund = suggestion.fund
    # 1. The statement as text (X18 raises for a scanned PDF)
    text = FinancialStatementMappingPrompt.document_text(suggestion)
    period_start = [suggestion.effective_period_start, suggestion.as_at_date].min
    # 2. Every fund-level entry the fund has up to today, largest first (the prompt keeps the first 400).
    # The draft is mapping only: the AI matches names to printed lines; amounts are a hint, never compared
    entries = entries_for_ai(fund, period_start, suggestion.as_at_date)
    # 3. Ask the AI with the entity's own keys/model
    prompt = FinancialStatementMappingPrompt.build(text:, entries:, existing_accounts: FinancialStatementAccount.where(fund_id: fund.id).ordered.pluck(:name),
                                                   as_at: suggestion.as_at_date, period_start:)
    raw = LlmService.ruby_llm_chat(entity: fund.entity).ask(prompt)
    # 4. Validate: drop invented entries (E27), bad enums, double claims
    answer = FinancialStatementMappingPrompt::LlmJson.parse(raw)
    proposal = FinancialStatementMappingPrompt.parse(answer, entries:)
    proposal["entries"] = entries.map { |e| e.transform_values(&:to_s) }
    proposal["as_at"] = suggestion.as_at_date.iso8601
    proposal["period_start"] = period_start.iso8601
    # The AI's own answer is kept, so changing the dates can re-check it against that date's entries
    proposal["ai_answer"] = answer
    # 5. Recompute every line and compare with the printed figure (H11 ✓ / E18 ⚠)
    suggestion.update!(proposal:, error: nil)
    # CapHive's own corrections (signs, net result rows), then New / Changed / Same tags
    suggestion.normalise!
    suggestion.tag_changes!
    suggestion.update!(status: "ready")
    notify(suggestion, "Your financial statement mapping draft for #{fund.name} is ready to review.", :success)
  rescue StandardError => e
    Rails.logger.error { "FinancialStatementMappingSuggestJob: suggestion #{suggestion_id}: #{e.class}: #{e.message}" }
    # X12 (AI failure) / X18 (no text): the reason is shown on the draft page with Retry
    message = e.is_a?(FinancialStatementMappingPrompt::Unreadable) ? e.message : "The AI draft failed: #{e.message.truncate(300)}"
    suggestion&.update_columns(status: "failed", error: message, updated_at: Time.current)
    notify(suggestion, "The mapping draft for #{suggestion.fund.name} failed. Open it to retry.", :danger) if suggestion
  end

  private

  # Every fund-level entry up to the draft's date (today), with its amounts as a hint for the AI
  def entries_for_ai(fund, period_start, as_at)
    FinancialStatementCalculator.new(fund:, start_date: period_start, end_date: as_at).entry_totals.sort_by { |e| -e["balance"].to_d.abs }
  end

  def notify(suggestion, message, level)
    UserAlert.new(user_id: suggestion.user_id, message:, level:).broadcast
  rescue StandardError => e
    Rails.logger.warn { "FinancialStatementMappingSuggestJob: toast failed: #{e.message}" }
  end
end
