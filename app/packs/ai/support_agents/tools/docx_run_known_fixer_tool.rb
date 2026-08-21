# frozen_string_literal: true

# RubyLLM tool: runs one of the app's existing deterministic docx post-
# processors (already applied to every generated document by
# DocumentGeneratorBase) against the current in-progress state. These fix
# narrow, previously-seen bug patterns — a hidden vanish-flagged counter-setter
# paragraph confusing LibreOffice's numbering, or formatting LibreOffice drops
# on round-trip. Worth trying before hand-editing XML for a numbering/spacing
# complaint, since it may already be the known cause.
#
# @see DocxNumberingFixer
# @see DocxFormattingPreserver
# @see DocxWorkspace#apply_external_fixer!
class DocxRunKnownFixerTool < RubyLLM::Tool
  description "Runs a known, deterministic fixer against the document's current " \
              "state: 'numbering' fixes hidden counter-setter paragraphs that make " \
              "LibreOffice render a ghost/duplicate list number a heading style " \
              "anchors to; 'formatting' restores formatting LibreOffice drops on " \
              "round-trip. Both are already applied to every normally-generated " \
              "document, so they're worth trying first for a numbering or " \
              "formatting complaint — but they only fix their specific known " \
              "pattern, not general issues like an un-converted conditional block."

  param :fixer, type: :string, desc: "'numbering' or 'formatting'.", required: true

  def initialize(workspace:)
    super()
    @workspace = workspace
  end

  def execute(fixer: nil)
    case fixer
    when "numbering"
      @workspace.apply_external_fixer! { |path| DocxNumberingFixer.fix!(path) }
      @workspace.record_change("Ran DocxNumberingFixer (known hidden-counter-setter pattern)")
      "OK. Ran the known numbering fixer. Use DocxRenderPreviewTool to check whether it resolved the issue."
    when "formatting"
      @workspace.apply_external_fixer! { |path| DocxFormattingPreserver.apply!(path) }
      @workspace.record_change("Ran DocxFormattingPreserver (known formatting round-trip pattern)")
      "OK. Ran the known formatting fixer. Use DocxRenderPreviewTool to check whether it resolved the issue."
    else
      "Error: fixer must be 'numbering' or 'formatting'."
    end
  end
end
