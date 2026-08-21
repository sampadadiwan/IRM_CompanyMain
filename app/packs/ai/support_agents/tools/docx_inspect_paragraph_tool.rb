# frozen_string_literal: true

# RubyLLM tool: dumps one paragraph's text, style, numbering (ilvl/numId), and
# raw pPr XML by its stable index within a part — the diagnostic step that
# revealed the Heading4/keepNext and numId-mismatch bugs in Individual.docx.
#
# @see DocxWorkspace#inspect_paragraph
class DocxInspectParagraphTool < RubyLLM::Tool
  description "Returns full detail for one paragraph: its text, paragraph style, " \
              "numbering (ilvl/numId if any), and the raw <w:pPr> XML. Use this " \
              "after DocxSearchTextTool to understand exactly why a paragraph is " \
              "numbered or paginated the way it is before deciding on a fix."

  param :part, type: :string, desc: "Part containing the paragraph, e.g. 'word/document.xml'.", required: true
  param :index, type: :integer, desc: "Paragraph index (from DocxSearchTextTool results).", required: true

  def initialize(workspace:)
    super()
    @workspace = workspace
  end

  def execute(part: nil, index: nil)
    result = @workspace.inspect_paragraph(part, index)
    return "No paragraph at index #{index} in #{part}." unless result

    <<~SUMMARY
      Index: #{result[:index]}
      Style: #{result[:style] || '(none — DefaultText/Normal)'}
      Numbering: ilvl=#{result[:ilvl].inspect} numId=#{result[:numId].inspect}
      Text: #{result[:text]}
      Raw pPr: #{result[:ppr_xml] || '(no pPr element)'}
    SUMMARY
  rescue DocxWorkspace::InvalidPart => e
    "Error: #{e.message}"
  end
end
