# frozen_string_literal: true

# The answer layout every AI chat screen draws as cards (AiChatHelper#ai_answer_html): Summary as a card,
# Key figures as stat cards, Details, and Follow-ups as buttons above the question box. One text, appended
# to each assistant's system prompt — the Support Console brief, the Assistants page (BaseAssistant), the
# floating agent window (GenericChatAgent, web channel only) and the record chat (ChatStreamJob).
#
# @see openspec/changes/ai-chat-kit/design.md (phase 7 — the answer layout)
module AiChatAnswerLayout
  # How amounts are written: stored as cents, shown in currency (asked for in the Support Console first).
  AMOUNTS = <<~TEXT.squish
    Amounts: a column ending in _cents stores the amount multiplied by 100. Never show a raw _cents value
    or an amount without its currency. Divide by 100 and write it the way the app does, in the record's own
    currency (its currency or folio_currency column), else its fund's: INR as ₹ with Indian grouping
    (₹20,00,000), other currencies with their symbol or code and standard grouping ($1,250,000). This applies
    to tables and Key figures too.
  TEXT

  # The headings the chat screens turn into cards and buttons.
  LAYOUT = <<~TEXT.strip
    Write the answer in markdown, laid out under these headings, in this order, leaving out any that has
    nothing to say. Do not write HTML yourself; a chart or HTML a tool returns goes in Details exactly as
    returned.
    ## Summary — the conclusion in two or three sentences.
    ## Key figures — the numbers that matter, one bullet each as "- **Label:** value".
    ## Details — the working: explanation, tables for row-level data, and any chart.
    ## Follow-ups — 2 or 3 questions the user is likely to ask next, written as the user would
    ask them, one bullet each. If you need something from the user, write it as a follow-up
    they can send.
  TEXT

  # @return [String] the amounts rule and the layout, ready to append to a system prompt
  def self.instructions
    "#{AMOUNTS}\n#{LAYOUT}"
  end
end
