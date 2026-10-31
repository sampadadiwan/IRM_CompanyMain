# frozen_string_literal: true

# The answer layout every AI chat screen draws as cards (AiChatHelper#ai_answer_html): Summary as a card,
# Key figures as stat cards, Details, and Follow-ups as buttons above the question box — plus optional
# widgets (Verdict, Checks, What to do) the assistant adds only when the question calls for one. One text,
# appended to each assistant's system prompt — the Support Console brief, the Assistants page
# (BaseAssistant), the floating agent window (GenericChatAgent, web channel only) and the record chat
# (ChatStreamJob).
#
# @see openspec/changes/ai-chat-kit/design.md (phase 7 — the answer layout; phase 8 — widgets)
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

  # Optional widgets, each with the condition that calls for it (a catalogue, not a form to fill in).
  # The renderer turns a well-formed one into its component and leaves a malformed one as plain text.
  WIDGETS = <<~TEXT.strip
    Optional sections — add one only when its condition holds. Most answers need none; rarely use more
    than two. Never add one to fill space. Put them right after Summary.
    ## Verdict — only when the user asks whether something is correct, or why two things differ. Start
    with exactly one of Matches, Mismatch or Can't tell, then a dash and one sentence. Not for questions
    that ask to list, count or show something.
    ## Checks — only when you compared figures against each other to reach the answer. One bullet per
    check, starting with ✓ when it holds or ✗ when it does not, e.g. "- ✓ Remittances add up to the called
    total". Not for restating figures you did not compare, and not for questions that ask to list, count
    or show something — even when you add the rows up.
    ## What to do — only when fixing the problem needs someone to change data or settings. Numbered
    steps, each naming the screen and button, e.g. "1. Open Capital Calls › Call 3 › Edit and …". Not when
    nothing needs to change.
    In a table, give each row's status its plain word (Paid, Pending, Overdue…) in a Status column.
    Examples of choosing:
    - "How many commitments does Fund I have?" → Summary only (no Verdict, no Checks).
    - "List Fund I's capital calls." → Summary only (no Checks, even with a total row).
    - "Why is TSTF2 marked Overpaid?" → Summary, Verdict, Checks.
    - "How do I correct the commitment's exchange rate?" → Summary, What to do.
  TEXT

  # The sections a rendered answer can have, by heading (for logging which ones an answer used).
  SECTION_HEADINGS = {
    "summary" => /\A(summary|final analysis|conclusion|answer|in short)\z/i,
    "key_figures" => /\A(key figures|key numbers|figures|stats|statistics)\z/i,
    "verdict" => /\Averdict\z/i,
    "checks" => /\Achecks?\z/i,
    "what_to_do" => /\A(what to do|how to fix( it)?|next steps)\z/i,
    "details" => /\Adetails\z/i,
    "questions" => /\A(questions|open questions|questions for you)\z/i,
    "follow_ups" => /\A(follow-?ups?|follow-?up questions|suggested questions|next questions)\z/i,
    "sources" => /\Awhere this comes from\z/i
  }.freeze

  # @return [String] the amounts rule, the layout and the optional widgets, ready to append to a prompt
  def self.instructions
    "#{AMOUNTS}\n#{LAYOUT}\n#{WIDGETS}"
  end

  # The layout sections an answer used, in order — read from its markdown headings (## or **bold** lines).
  #
  # @param text [String, nil] the answer's markdown
  # @return [Array<String>] e.g. ["summary", "verdict", "checks"]
  def self.sections_in(text)
    text.to_s.each_line.filter_map do |line|
      title = line.strip.sub(/\A#+\s*/, "").delete_prefix("**").delete_suffix("**").delete_suffix(":").strip
      next unless line.strip.start_with?("#", "**")

      SECTION_HEADINGS.find { |_name, pattern| title.match?(pattern) }&.first
    end
  end

  # Logs which sections an answer used, so over-use of a widget shows up in the logs (one line per answer).
  #
  # @param source [String] which chat answered (e.g. "assistants", "support_console")
  # @param text [String, nil] the answer's markdown
  def self.log_usage(source, text)
    Rails.logger.info { "[ai_chat] answer sections source=#{source} sections=#{sections_in(text).join(',').presence || 'none'}" }
  end
end
