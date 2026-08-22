# frozen_string_literal: true

# RubyLLM tool: sets paragraph indentation (left, hanging, first_line) in dxa units
# (1 inch = 1440 dxa, 0.5 inch = 720 dxa).
#
# @see DocxWorkspace#set_paragraph_indentation!
class DocxSetParagraphIndentationTool < RubyLLM::Tool
  description "Sets explicit indentation (left, hanging, first_line in dxa units, where " \
              "720 dxa = 0.5 in, 1440 dxa = 1.0 in) on a paragraph's <w:ind> properties. " \
              "Use this to fix sub-clause indentation or hanging indents."

  param :part, type: :string, desc: "Part containing the paragraph, e.g. 'word/document.xml'.", required: true
  param :index, type: :integer, desc: "Paragraph index to modify.", required: true
  param :left, type: :integer, desc: "Left indent in dxa (e.g. 720 or 1440).", required: false
  param :hanging, type: :integer, desc: "Hanging indent in dxa (e.g. 720).", required: false
  param :first_line, type: :integer, desc: "First line indent in dxa.", required: false

  def initialize(workspace:)
    super()
    @workspace = workspace
  end

  def execute(part: nil, index: nil, left: nil, hanging: nil, first_line: nil)
    @workspace.set_paragraph_indentation!(part, index, left: left, hanging: hanging, first_line: first_line)
    @workspace.record_change(
      "Paragraph #{index} in #{part}: ind set to left=#{left} hanging=#{hanging} first_line=#{first_line}"
    )
    "OK. Paragraph #{index} indentation updated."
  rescue DocxWorkspace::InvalidPart, ArgumentError => e
    "Error: #{e.message}"
  end
end
