# frozen_string_literal: true

# Runs an LLM tool-calling (ReAct) loop against an uploaded .docx template to
# diagnose and fix a user-described problem (wrong/duplicate numbering,
# pagination gaps, an un-converted conditional variant, etc.), then saves the
# result as a new draft Document for human review. The source template is
# never modified.
#
# The loop itself is RubyLLM's own tool-calling `Chat#ask` (same mechanism
# BaseAssistant wraps for the chat assistants), already iteration-capped by
# config/initializers/ruby_llm_patch.rb — no bespoke while-loop needed here.
#
# @see DocxWorkspace
# @see SupportAgentService
# @see TemplateFixJob
class TemplateFixAgent < SupportAgentService
  # For rendering the fix summary into the draft Document's rich-text `text`
  # field the same way the "Fix Me result" panel renders it — see
  # write_draft_notes! below. Same inclusion pattern as ReportInsightMailer.
  include MarkdownHelper

  DESCRIPTION = "Diagnoses and fixes a reported STRUCTURAL problem (numbering, " \
                "indentation, pagination) in an uploaded .docx template using an " \
                "AI tool-calling loop over the raw document XML, and produces a " \
                "new draft document for review. The source template is never " \
                "modified. Never creates or edits Sablon merge fields/conditionals " \
                "— an unconverted conditional is diagnosed and reported, not fixed."

  LONG_DESCRIPTION = <<~DESC
    Fixes reported STRUCTURAL problems in a Word template — duplicate or incorrect
    clause numbering, or unexpected blank space/page breaks. Triggered from the
    "Fix Me" button on a template document with a plain-English description of
    the problem, not run on a schedule or in batch.

    Does NOT fix Sablon merge-field/conditional problems (e.g. a section that
    renders for every investor when it should only apply to one type) — it
    diagnoses and reports those in its summary for a human (or a separate,
    dedicated agent) to complete; it never creates or edits a merge field.

    Steps:
    • Initialize Agent — loads the template and prepares a private working copy;
      the original document is never touched.
    • Run Fix Loop — an AI tool-calling loop searches, inspects, and edits the
      template's underlying structure, then renders a preview to confirm the
      fix before finishing.
    • Finalize Fix — validates the result and saves it as a new, separately
      named draft document for review, alongside a summary of what changed.

    Nothing goes live automatically: the draft is always a new document, and a
    human decides whether to use it in place of the existing template.
  DESC

  # Higher than the assistants' typical AI_TIMEOUT (180s) — a 50-turn budget
  # with repeated libreoffice preview renders can legitimately take several minutes.
  AI_TIMEOUT = ENV.fetch("TEMPLATE_FIX_TIMEOUT", "600").to_i.seconds
  # 60 proved insufficient for a run covering 3 simultaneous issues: observed
  # live, the model spent its entire 60-turn budget on read-only
  # investigation (49 of 60 calls were docx_inspect_paragraph) despite having
  # located everything it needed for the edit within its first 5 calls, and
  # never made a single edit. Raised to 80 for headroom; the real fix is the
  # "commit once you have enough info" instruction above — this alone won't
  # solve indecisiveness, it just delays hitting the wall.
  MAX_TOOL_ITERATIONS = ENV.fetch("TEMPLATE_FIX_MAX_TOOL_ITERATIONS", "80").to_i

  SYSTEM_PROMPT = <<~PROMPT
    You are a meticulous Word document (.docx / OOXML) template-repair assistant
    for a fund administration platform. Templates are Sablon merge templates used
    to generate legal documents (commitment agreements, KYC forms, notices).

    You have tools to search, inspect, and surgically edit the underlying XML,
    and to render the CURRENT state to PDF text so you can verify your fix.

    Rules you must follow:
    - Clause numbers like "5.2.9" are almost never literal text — Word computes
      them from <w:numPr> (ilvl/numId), so searching document.xml for "5.2.9" or
      "5.3" will find nothing. Search for the surrounding clause TEXT instead
      (e.g. "None of the following"), then use DocxInspectParagraphTool to read
      its actual ilvl/numId, and DocxListNumberingTool to see how that numId's
      counter is configured (lvlOverride/startOverride).
    - A frequent root cause of "duplicate/wrong numbering after section X"
      complaints in this app's templates: the source document contains two
      alternate variants of a section (e.g. for different investor/contributor
      types) that were meant to be Sablon conditionals but were left as literal
      drafting placeholders like "[A] ..." / "[B] ..." — both render
      unconditionally, and their independent numId counters produce duplicate-
      looking clause numbers. Early on, search document.xml for square-bracket
      markers ("[A]", "[B]", or similar short bracketed labels) near the
      reported section — finding one of these is a strong, fast signal.
      YOU MUST NOT FIX THIS YOURSELF — you have no tool to create a Sablon
      merge field/conditional, and must not invent one or write literal "«...»"
      text with DocxReplaceParagraphTextTool (Sablon does not recognize that as
      a real field, and a human still has to supply the correct app-specific
      boolean expression, e.g. "investor_kyc.individual?" — that decision
      belongs to a separate, dedicated agent, not this one). Once you've found
      the bracket markers (or confirmed the pattern some other way), STOP
      investigating it further: do not keep searching for the "right" merge
      field expression, do not inspect every paragraph in either variant block.
      Just note the paragraph indices/range of both blocks in your closing
      summary as something a human (or the Sablon-conditional agent) needs to
      fix, and move on to whatever else the reported issue covers. Spending
      tool-call budget investigating a fix you're not going to make is a
      failure, not diligence.
    - A frequent root cause of "large blank space" / "content pushed to the next
      page" complaints: a paragraph style's <w:keepNext/> chains several
      consecutive same-style paragraphs (e.g. Heading4 on a run of "X.Y.Z"
      sub-clauses like 5.2.9.1-5.2.9.6) into one unbreakable block; when that
      whole block doesn't fit the remaining space on a page, LibreOffice pushes
      the ENTIRE block to the next page instead of splitting it, leaving the gap
      behind. A static scan for this (DocxWorkspace#keepnext_repeated_styles)
      already ran before you started and, if it found anything, its candidates
      are listed at the end of your initial prompt — check those FIRST if the
      reported issue matches this symptom (do NOT rely on spotting a blank page
      by eye in a rendered preview's text dump: pdftotext -layout does not
      represent a large visual gap as a proportionally blank page, since the
      page still carries its real preceding text plus a page-number footer —
      confirmed live, this makes the gap invisible in extracted text). A
      candidate isn't automatically a confirmed bug — some keepNext clusters are
      legitimate (e.g. several short boilerplate sections in a row, each with
      its own body paragraph) — verify against the actual reported symptom
      before touching one. Once confirmed: DocxInspectParagraphTool the first
      paragraph(s) on the page right after the gap to find their style, then
      DocxSetStylePropertyTool(style_id: <that style>, property: "keepNext",
      enabled: false). Never "fix" this by shortening or deleting content to
      make it fit.
    - word/styles.xml has NO body-paragraph text — do not repeatedly search it
      for a style's own name (e.g. searching "Heading4" in styles.xml). The
      style ID you need (e.g. "Heading4") comes from DocxInspectParagraphTool's
      `style:` field on a paragraph using that style; once you have it, call
      DocxSetStylePropertyTool with that style_id directly — no need to verify
      it exists in styles.xml first. DocxSearchTextTool on styles.xml IS
      supported (matches styleId/display name), just don't loop on it.
    - Work iteratively: search/inspect BEFORE editing, and render a preview AFTER
      editing to confirm the fix actually worked before finishing. As soon as ONE
      preview after your edits confirms the problem is resolved, STOP investigating
      and write your closing summary immediately — do not keep re-searching or
      re-rendering to double- and triple-check an already-confirmed fix. You have
      a limited number of tool calls; running out AFTER the fix is done but BEFORE
      you report it is a failure, not extra diligence.
    - NEVER delete substantive legal/clause text. If you believe content should be
      removed, say so in your final summary instead — a human will decide.
    - This agent fixes template STRUCTURE only (numbering, indentation,
      pagination/style properties) — it never creates, edits, or reasons about
      Sablon merge fields or conditionals. If the reported issue is really a
      Sablon/merge-field problem (a field showing the wrong value, a missing
      merge field, an "[A]/[B]"-style unconverted conditional — see above),
      diagnose and describe it in your summary, but do not attempt to fix it.
    - The known formatting and numbering fixers (what DocxRunKnownFixerTool runs)
      have ALREADY been applied deterministically before you were invoked — do not
      call DocxRunKnownFixerTool again unless you've made your own edits that you
      specifically believe would benefit from re-running one (rare). Start by
      rendering a preview of the CURRENT (post-fixer) state and searching/inspecting
      only the specific clauses named in the reported issue, so you don't burn your
      tool budget re-discovering fixes those two passes already made.
    - You have a limited number of tool calls. Be efficient: don't re-inspect a
      paragraph you've already inspected, don't re-render a preview after a
      no-op investigation step, and don't search the same query twice.
    - When done, reply with a concise plain-text summary of what you changed and
      why, and flag anything you noticed but deliberately left alone.
  PROMPT

  step :initialize_agent
  step :run_fix_loop
  step :finalize_fix

  def targets(entity_id)
    Document.template.where(entity_id: entity_id)
  end

  def initialize_agent(ctx, document: nil, issue_description: nil, llm_model: nil, support_agent_report: nil, **)
    report = support_agent_report
    mark_step_running(report, :initialize_agent) if report

    super

    unless document&.template?
      Rails.logger.info { "[TemplateFixAgent] Document ID=#{document&.id} is not a template" }
      mark_step_failed(report, :initialize_agent, message: "Not a template document") if report
      return false
    end

    ctx[:document] = document
    ctx[:issue_description] = issue_description.to_s.strip
    if ctx[:issue_description].blank?
      mark_step_failed(report, :initialize_agent, message: "No issue description provided") if report
      return false
    end

    # Per-run model override (Fix Me modal's model picker) takes precedence
    # over the agent's configured default — super already set ctx[:llm] using
    # the latter, so only re-build the chat when the caller asked for a
    # specific different model.
    ctx[:llm] = LlmService.ruby_llm_chat(entity: @support_agent.entity, model: llm_model) if llm_model.present? && llm_model != @support_agent.effective_model

    ctx[:workspace] = DocxWorkspace.new(document)

    mark_step_success(report, :initialize_agent, message: "Ready") if report
    true
  end

  def run_fix_loop(ctx, document:, issue_description:, workspace:, llm:, support_agent_report: nil, **)
    report = support_agent_report
    mark_step_running(report, :run_fix_loop) if report

    llm.with_instructions(SYSTEM_PROMPT)
    llm.with_tools(*build_tools(workspace))
    # Real templates run to thousands of paragraphs across hundreds of numbering
    # definitions — the global 25-turn default (config/initializers/ruby_llm_patch.rb,
    # tuned for simpler KPI-batching queries) isn't enough headroom for a genuine
    # search-inspect-edit-verify cycle on a document this size.
    llm.max_tool_iterations = MAX_TOOL_ITERATIONS if llm.respond_to?(:max_tool_iterations=)

    # Run the two known deterministic fixers up front rather than leaving it to the
    # LLM's judgement to call DocxRunKnownFixerTool early: observed live on a
    # 2,800-paragraph template, an unconstrained ReAct loop spent its entire
    # turn budget manually searching/inspecting individual paragraphs and never
    # got around to calling the known fixer at all, exhausting the budget with
    # zero edits made (see docs/modules/documents/template_fix_agent_handover_note.md #6).
    # Applying them here guarantees the 90%-of-cases fix always happens, and
    # leaves the model's whole budget for the residual, document-specific issue.
    workspace.apply_external_fixer! { |path| DocxFormattingPreserver.apply!(path) }
    workspace.record_change("Ran DocxFormattingPreserver (known formatting round-trip pattern)")
    workspace.apply_external_fixer! { |path| DocxNumberingFixer.fix!(path) }
    workspace.record_change("Ran DocxNumberingFixer (known hidden-counter-setter pattern)")

    # Static structural scan for the "blank page after heading" pagination bug
    # (keepNext chaining a cluster of same-style paragraphs into one
    # unbreakable block — see DocxWorkspace#keepnext_repeated_styles). Surfaced
    # directly in the prompt, for free, rather than relying on the model to
    # notice a large blank gap by reading a page-text dump (confirmed
    # unreliable: pdftotext -layout does not represent the gap proportionally,
    # since the page still carries real preceding text plus its page-number
    # footer). These are CANDIDATES, not confirmed bugs — some keepNext
    # clusters are legitimate (e.g. several short boilerplate sections in a
    # row, each with its own body paragraph) — the model must still verify
    # against the actual reported symptom and a render before touching one.
    keepnext_hint = ""
    risks = workspace.keepnext_repeated_styles
    if risks.any?
      lines = risks.map { |r| "- style '#{r[:style_id]}' clusters #{r[:clustered_count]} times starting near paragraph index #{r[:start_index]}" }
      keepnext_hint = <<~HINT

        Static scan found keepNext paragraph style(s) clustered tightly enough to risk the
        "blank page / content pushed to next page" pagination bug (see system prompt):
        #{lines.join("\n")}
        These are candidates, not confirmed bugs. If the reported issue mentions a blank
        space or content jumping to the next page, inspect one of these clusters first
        (DocxInspectParagraphTool) before searching elsewhere.
      HINT
    end

    prompt = <<~PROMPT
      The user reported this problem with the template "#{document.name}":

      #{issue_description}

      The known formatting and numbering fixers have already been run against this
      document (see the two changes already in the log) — they fix the majority of
      indentation/spacing/numbering round-trip issues automatically. Start by
      rendering a preview to see the CURRENT state and check whether the reported
      problem is already resolved. Only search/inspect/edit further for whatever
      part of the problem remains. When you are done, reply with a plain-text
      summary of what you changed (including confirming what the known fixers
      already handled).
      #{keepnext_hint}
    PROMPT

    response = Timeout.timeout(AI_TIMEOUT) { llm.ask(prompt) }
    ctx[:agent_summary] = response.content.to_s

    # The global tool-iteration cap (config/initializers/ruby_llm_patch.rb) fails
    # "safe" by returning a synthetic message rather than raising — but observed
    # live, the model can burn its remaining budget re-verifying an ALREADY-
    # correct fix (extra searches/renders after the real edits are done) and hit
    # this with real, good changes already in workspace.change_log. Treat it as
    # degraded, not a clean success: a human should double-check the change log
    # against the preview rather than trust an agent that never got to say "done".
    if ctx[:agent_summary].start_with?("Error: Maximum tool execution limit reached")
      ctx[:agent_error] = true
      ctx[:agent_summary] = if workspace.change_log.any?
                              "The agent made #{workspace.change_log.size} change(s) (see below) but ran out of " \
                                "its tool-call budget before writing a closing summary — it may not have finished " \
                                "verifying the fix. Review the changes and the rendered preview carefully."
                            else
                              "The agent ran out of its tool-call budget before making any changes or reaching a " \
                                "diagnosis. Try re-running, or narrow the issue description."
                            end
    end

    mark_step_success(report, :run_fix_loop, message: "Fix loop complete") if report
    true
  rescue Timeout::Error
    ctx[:agent_summary] = "Timed out after #{AI_TIMEOUT}s before finishing. Saving whatever state was reached."
    ctx[:agent_error] = true
    mark_step_failed(report, :run_fix_loop, message: "Timed out") if report
    true # still let finalize_fix render/save + report whatever partial edits exist
  rescue StandardError => e
    Rails.logger.error { "[TemplateFixAgent] run_fix_loop error: #{e.message}" }
    Rails.logger.error { e.backtrace.join("\n") }
    ctx[:agent_summary] = "Error: #{e.message}"
    ctx[:agent_error] = true
    mark_step_failed(report, :run_fix_loop, message: e.message) if report
    true
  end

  def finalize_fix(ctx, workspace:, support_agent_report: nil, **)
    report = support_agent_report
    mark_step_running(report, :finalize_fix) if report

    # Hard content-preservation gate (paragraph count, word count, and every
    # word itself must be unchanged from the original — see
    # DocxWorkspace#validate_content_unchanged!). Raises on any mismatch,
    # caught below: draft is not saved, report is blocked, and render_error
    # carries the exact diff so a human can see what happened.
    workspace.validate_content_unchanged!

    preview = workspace.render_preview!
    changes = workspace.change_log

    unless preview[:success]
      write_report(report, summary: ctx[:agent_summary], changes: changes, render_error: preview[:error], content_check: workspace.content_check)
      mark_step_failed(report, :finalize_fix, message: "Final render failed — draft not saved") if report
      finalize_report(report, status: "blocked") if report
      return false
    end

    draft = workspace.save_as_new_document!
    write_draft_notes!(draft, summary: ctx[:agent_summary], changes: changes, content_check: workspace.content_check)

    write_report(report, summary: ctx[:agent_summary], changes: changes, result_document_id: draft.id,
                          page_count: preview[:page_count], content_check: workspace.content_check)
    mark_step_success(report, :finalize_fix, message: "Draft ready: #{draft.name}") if report
    finalize_report(report, status: ctx[:agent_error] ? "blocked" : "ready") if report
    true
  rescue StandardError => e
    Rails.logger.error { "[TemplateFixAgent] finalize_fix error: #{e.message}" }
    Rails.logger.error { e.backtrace.join("\n") }
    write_report(report, summary: ctx[:agent_summary], changes: workspace.change_log, render_error: e.message, content_check: workspace.content_check)
    mark_step_failed(report, :finalize_fix, message: e.message) if report
    finalize_report(report, status: "blocked") if report
    false
  ensure
    workspace.cleanup!
  end

  private

  def build_tools(workspace)
    [
      DocxSearchTextTool.new(workspace: workspace),
      DocxInspectParagraphTool.new(workspace: workspace),
      DocxListNumberingTool.new(workspace: workspace),
      DocxSetParagraphNumberingTool.new(workspace: workspace),
      DocxSetParagraphIndentationTool.new(workspace: workspace),
      DocxReplaceParagraphTextTool.new(workspace: workspace),
      # DocxInsertMergeFieldTool.new(workspace: workspace), # disabled: TemplateFixAgent
      # must never create Sablon merge fields/conditionals — an unconverted "[A]"/"[B]"
      # block is now DETECTED and REPORTED only (see system prompt), not fixed here.
      # That capability belongs to a separate, not-yet-built agent.
      DocxSetStylePropertyTool.new(workspace: workspace),
      DocxRenderPreviewTool.new(workspace: workspace),
      DocxRunKnownFixerTool.new(workspace: workspace)
    ]
  end

  # Writes the same information the "Fix Me result" panel shows (see
  # app/packs/core/documents/views/documents/_fix_me.html.erb) onto the draft
  # Document's own rich-text `text` field, so it travels with the file itself
  # (e.g. visible on the document's own show page) rather than only living in
  # the SupportAgentReport a human has to separately go find.
  def write_draft_notes!(draft, summary:, changes:, content_check:)
    parts = []
    parts << markdown_to_html(summary) if summary.present?

    if changes.present?
      parts << "<p><strong>Changes made:</strong></p><ul>#{changes.map { |c| "<li>#{ERB::Util.html_escape(c)}</li>" }.join}</ul>"
    end

    if content_check.present?
      para = content_check[:paragraph_count] || {}
      words = content_check[:word_count] || {}
      passed = content_check[:passed]
      word_match = content_check[:word_for_word_match]
      parts << <<~HTML
        <p><strong>Content check — #{passed ? "PASS" : "FAIL"}</strong></p>
        <ul>
          <li>Paragraph count: #{para[:original]} → #{para[:fixed]}</li>
          <li>Word count: #{words[:original]} → #{words[:fixed]}</li>
          <li>Word-for-word match: #{word_match ? "Yes" : "No"}</li>
        </ul>
      HTML
    end

    return if parts.empty?

    draft.text = parts.join
    draft.save!
  end

  def write_report(report, summary:, changes:, result_document_id: nil, page_count: nil, render_error: nil, content_check: nil)
    return unless report

    report.json_fields = (report.json_fields || {}).merge(
      "fix_summary" => summary,
      "changes" => changes,
      "result_document_id" => result_document_id,
      "page_count" => page_count,
      "render_error" => render_error,
      "content_check" => content_check
    )
    report.json_fields_will_change!
    report.save
  end
end
