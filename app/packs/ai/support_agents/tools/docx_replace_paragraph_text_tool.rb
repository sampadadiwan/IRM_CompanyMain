# frozen_string_literal: true

# RubyLLM tool: replaces a paragraph's visible text, preserving its pPr
# (numbering, style, indentation) and the formatting of its first run.
#
# @see DocxWorkspace#replace_paragraph_text!
class DocxReplaceParagraphTextTool < RubyLLM::Tool
  description "Replaces the visible text of a paragraph with new text, keeping " \
              "its paragraph formatting (style, numbering, indentation) and the " \
              "font/size of its first run untouched. Use this for wording fixes " \
              "or to turn a leftover literal placeholder label (e.g. a stray " \
              "'[A] ...' drafting note) into plain text. This does NOT create a " \
              "Sablon merge field — use DocxInsertMergeFieldTool for that. " \
              "Never use this to delete substantive legal clause text; if a " \
              "clause looks like it should be removed, say so in your summary " \
              "instead so a human can decide."

  parameter :part, type: :string, description: "Part containing the paragraph.", required: true
  parameter :index, type: :integer, description: "Paragraph index to modify.", required: true
  parameter :text, type: :string, description: "New visible text for the paragraph.", required: true

  def initialize(workspace:)
    super()
    @workspace = workspace
  end

  def execute(part: nil, index: nil, text: nil)
    before = @workspace.inspect_paragraph(part, index)
    @workspace.replace_paragraph_text!(part, index, text)
    @workspace.record_change("Paragraph #{index} in #{part}: text \"#{before&.dig(:text)}\" -> \"#{text}\"")
    "OK. Paragraph #{index} text replaced."
  rescue DocxWorkspace::InvalidPart, ArgumentError => e
    "Error: #{e.message}"
  end
end
