# frozen_string_literal: true

# RubyLLM tool: sets/corrects the ilvl+numId a paragraph is numbered with,
# creating pPr/numPr if the paragraph had none (e.g. was silently inheriting
# numbering from its paragraph style default).
#
# @see DocxWorkspace#set_paragraph_numbering!
class DocxSetParagraphNumberingTool < RubyLLM::Tool
  description "Sets the numbering (ilvl + numId) on a paragraph, adding an " \
              "explicit override if it previously had none. Use this to fix a " \
              "paragraph that is numbered against the wrong list, or one that " \
              "was silently inheriting numbering from its style's default numId " \
              "instead of the list it visually belongs to."

  param :part, type: :string, desc: "Part containing the paragraph.", required: true
  param :index, type: :integer, desc: "Paragraph index to modify.", required: true
  param :ilvl, type: :integer, desc: "Numbering level (0-based).", required: true
  param :num_id, type: :string, desc: "The numId to assign (see DocxListNumberingTool).", required: true

  def initialize(workspace:)
    super()
    @workspace = workspace
  end

  def execute(part: nil, index: nil, ilvl: nil, num_id: nil)
    before = @workspace.inspect_paragraph(part, index)
    @workspace.set_paragraph_numbering!(part, index, ilvl: ilvl, num_id: num_id)
    @workspace.record_change(
      "Paragraph #{index} in #{part}: numbering ilvl=#{before&.dig(:ilvl).inspect}/numId=#{before&.dig(:numId).inspect} " \
      "-> ilvl=#{ilvl}/numId=#{num_id}"
    )
    "OK. Paragraph #{index} now uses ilvl=#{ilvl}, numId=#{num_id}."
  rescue DocxWorkspace::InvalidPart, ArgumentError => e
    "Error: #{e.message}"
  end
end
