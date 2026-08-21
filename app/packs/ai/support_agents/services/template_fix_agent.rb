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
  DESCRIPTION = "Diagnoses and fixes a reported problem in an uploaded .docx " \
                "template (numbering, pagination, un-converted conditionals) " \
                "using an AI tool-calling loop over the raw document XML, and " \
                "produces a new draft document for review. The source template " \
                "is never modified."

  LONG_DESCRIPTION = <<~DESC
    Fixes reported problems in a Word template — duplicate or incorrect clause
    numbering, unexpected blank space or page breaks, or a section that renders
    for every investor when it should only apply to one type. Triggered from the
    "Fix Me" button on a template document with a plain-English description of
    the problem, not run on a schedule or in batch.

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
  MAX_TOOL_ITERATIONS = ENV.fetch("TEMPLATE_FIX_MAX_TOOL_ITERATIONS", "60").to_i

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
      When you wrap such a block in a conditional, the correct expression is
      app-specific (e.g. "investor_kyc.individual?") — don't guess it. Search
      document.xml for existing «=...» merge fields to see what object names
      (e.g. "investor_kyc", "capital_commitment") are already in scope for this
      template, and prefer a "<object>.<boolean_method>?" name matching the
      distinction described in the two variants (e.g. individual? vs.
      non_individual?) over an invented field name.
    - Sablon supports exactly these operations, nothing else: '=expr' (value),
      'expr:if', 'expr:elsif'/'expr:elseIf', 'expr:else', 'expr:endIf',
      'expr:each(item)', 'expr:endEach'. THERE IS NO ':unless'. To show a block
      only when a condition is false, use the boolean's negation with ':if'
      (e.g. "foo.non_individual?:if" ... ":endIf"), or "X:if" ... "X:else" ...
      ":endIf". DocxInsertMergeFieldTool will reject anything else, but don't
      rely on that — get it right the first time.
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
    - To make part of a template conditional (e.g. an unconverted "[A]/[B]"-style
      variant marker), use DocxInsertMergeFieldTool to add real Sablon
      «expr:if»/«expr:endIf» merge fields — never write literal "«...»" text with
      DocxReplaceParagraphTextTool; Sablon does not recognize that as a field.
    - Inserting a paragraph shifts subsequent paragraph indices in that part —
      re-search rather than reusing a stale index from before an insertion.
    - Prefer DocxRunKnownFixerTool first for numbering/formatting complaints; it
      may already be the known cause, but it only fixes its one specific known
      pattern — if a preview afterward still shows the problem, move on to
      diagnosing it yourself rather than retrying the known fixer.
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
    llm.max_tool_iterations = MAX_TOOL_ITERATIONS

    prompt = <<~PROMPT
      The user reported this problem with the template "#{document.name}":

      #{issue_description}

      Diagnose the root cause and fix it directly in the template. When you are
      done, reply with a plain-text summary of what you changed.
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

    preview = workspace.render_preview!
    changes = workspace.change_log

    unless preview[:success]
      write_report(report, summary: ctx[:agent_summary], changes: changes, render_error: preview[:error])
      mark_step_failed(report, :finalize_fix, message: "Final render failed — draft not saved") if report
      finalize_report(report, status: "blocked") if report
      return false
    end

    draft = workspace.save_as_new_document!

    write_report(report, summary: ctx[:agent_summary], changes: changes, result_document_id: draft.id, page_count: preview[:page_count])
    mark_step_success(report, :finalize_fix, message: "Draft ready: #{draft.name}") if report
    finalize_report(report, status: ctx[:agent_error] ? "blocked" : "ready") if report
    true
  rescue StandardError => e
    Rails.logger.error { "[TemplateFixAgent] finalize_fix error: #{e.message}" }
    Rails.logger.error { e.backtrace.join("\n") }
    write_report(report, summary: ctx[:agent_summary], changes: workspace.change_log, render_error: e.message)
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
      DocxReplaceParagraphTextTool.new(workspace: workspace),
      DocxInsertMergeFieldTool.new(workspace: workspace),
      DocxSetStylePropertyTool.new(workspace: workspace),
      DocxRenderPreviewTool.new(workspace: workspace),
      DocxRunKnownFixerTool.new(workspace: workspace)
    ]
  end

  def write_report(report, summary:, changes:, result_document_id: nil, page_count: nil, render_error: nil)
    return unless report

    report.json_fields = (report.json_fields || {}).merge(
      "fix_summary" => summary,
      "changes" => changes,
      "result_document_id" => result_document_id,
      "page_count" => page_count,
      "render_error" => render_error
    )
    report.json_fields_will_change!
    report.save
  end
end
