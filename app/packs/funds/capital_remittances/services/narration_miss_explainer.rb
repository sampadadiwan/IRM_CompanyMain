# Best-effort LLM explanation for bank deposit narrations that
# BankDepositNarrationParser could not match against any known transfer-rail format
# (pattern == 'UNMATCHED'). Batches every unparsed narration into a single LLM call -
# never one call per row, see NoteSummarizerAgent#tag_untagged_notes for the same
# batching convention - and is soft-fail throughout: any LLM/parsing error just leaves
# `explanations` empty rather than raising, since this is a diagnostic aid, not
# something that should ever block statement reconciliation.
#
# Usage:
#   result = NarrationMissExplainer.(narrations: ["FOO/BAR/9821", "XYZ REF 001"])
#   result[:explanations] # => { "FOO/BAR/9821" => "...", "XYZ REF 001" => "..." }
#   # narrations the LLM couldn't/didn't explain are simply absent from the hash
class NarrationMissExplainer < Trailblazer::Operation
  DEFAULT_MODEL = "gemini-3-flash-preview".freeze

  step :call_llm
  step :parse_response

  def call_llm(ctx, narrations:, model: nil, **)
    ctx[:raw_response] = LlmService.ruby_llm_chat(model: model || DEFAULT_MODEL).ask(build_prompt(narrations))
    true
  rescue StandardError => e
    Rails.logger.error { "[NarrationMissExplainer] LLM call failed: #{e.message}" }
    ctx[:explanations] = {}
    false
  end

  def parse_response(ctx, narrations:, **)
    raw_content = extract_text_content(ctx[:raw_response])

    # The model is asked for a bare JSON object but may still wrap it in a code fence.
    json_match = raw_content.match(/```json\s*(\{.+?\})\s*```/m) ||
                 raw_content.match(/```\s*(\{.+?\})\s*```/m) ||
                 raw_content.match(/(\{.+\})/m)

    unless json_match
      Rails.logger.warn { "[NarrationMissExplainer] LLM returned no parseable JSON" }
      ctx[:explanations] = {}
      return true
    end

    by_index = JSON.parse(json_match[1])
    # Map back from the index used in the prompt to the original narration text, keeping
    # only entries the model actually answered (ignore missing/hallucinated indices).
    ctx[:explanations] = narrations.each_with_index.filter_map do |text, i|
      explanation = by_index[i.to_s]
      [text, explanation] if explanation.present?
    end.to_h
    true
  rescue StandardError => e
    Rails.logger.error { "[NarrationMissExplainer] Parsing LLM response failed: #{e.message}" }
    ctx[:explanations] = {}
    true
  end

  private

  def build_prompt(narrations)
    numbered = narrations.each_with_index.map { |text, i| "[#{i}] #{text}" }.join("\n")

    <<~PROMPT
      You are helping reconcile an Indian bank statement. Below are raw bank transaction
      narrations ("Transaction Remarks"/"Particulars") for deposit rows that a pattern-matching
      parser could not recognize as any known transfer-rail format (RTGS, NEFT, IMPS, CLG,
      MOB/TPFT, BIL/INFT, TRF, and similar).

      For each numbered narration below, write ONE short sentence: say what payment
      method/rail it looks like it came from and why an automated parser likely can't
      reliably extract a depositor name/account number from it - or, if it actually does
      look like it contains a usable name/account, say so and note it needs a manual regex.

      Narrations:
      #{numbered}

      Respond with ONLY a JSON object mapping each index (as a string) to your one-sentence
      explanation, e.g. {"0": "...", "1": "..."}. No markdown, no other text.
    PROMPT
  end

  def extract_text_content(response)
    return response.to_s unless response.respond_to?(:content)

    content = response.content
    content.to_s
  end
end
