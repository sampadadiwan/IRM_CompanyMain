# frozen_string_literal: true

# RubyLLM tool: substring-searches a docx part's paragraph text and returns
# matching paragraph indices + text — the entry point for locating the
# paragraphs relevant to the reported problem before inspecting/editing them.
#
# @see DocxWorkspace#find_matches
# @see TemplateFixAgent
class DocxSearchTextTool < RubyLLM::Tool
  description "Searches for text within a .docx part (document.xml, styles.xml, " \
              "or a header/footer part) and returns the matching paragraphs with " \
              "their stable index. Use this first to locate the paragraphs " \
              "relevant to the reported problem — document.xml is too large to " \
              "read in full. Search text is a plain substring match, not a regex. " \
              "For word/styles.xml specifically, this matches against style IDs " \
              "and display names instead (e.g. 'Heading4' or 'heading 4') since " \
              "style definitions have no body paragraph text to search."

  param :part, type: :string,
               desc: "Which part to search, e.g. 'word/document.xml' or 'word/styles.xml'.",
               required: true
  param :query, type: :string, desc: "Text fragment to search for.", required: true
  param :limit, type: :integer, desc: "Max matches to return (default 20).", required: false

  def initialize(workspace:)
    super()
    @workspace = workspace
  end

  def execute(part: nil, query: nil, limit: 20)
    matches = @workspace.find_matches(part, query, limit: (limit || 20).to_i)
    return "No matches for \"#{query}\" in #{part}." if matches.empty?

    if part == "word/styles.xml"
      matches.map { |m| "styleId=#{m[:style_id]} name=#{m[:name].inspect}\n  pPr: #{m[:ppr_xml] || '(none)'}" }.join("\n\n")
    else
      matches.map { |m| "[#{m[:index]}] #{m[:text].truncate(220)}" }.join("\n")
    end
  rescue DocxWorkspace::InvalidPart, ArgumentError => e
    "Error: #{e.message}"
  end
end
