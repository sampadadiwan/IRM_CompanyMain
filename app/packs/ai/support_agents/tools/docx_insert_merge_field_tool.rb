# frozen_string_literal: true

# RubyLLM tool: inserts a new paragraph containing a real Word merge field
# (Sablon «=expr», «expr:if», «expr:else», «expr:endIf», or «expr:each(x)»/
# «expr:endEach») immediately before/after an existing paragraph.
#
# This is deliberately the ONLY way tools can create a merge field — a plain
# text run containing literal "«...»" characters is inert to Sablon (it parses
# real Word field codes, not literal guillemet text), which is exactly the
# mistake that had to be caught and fixed by hand while building this agent.
#
# @see DocxWorkspace#insert_merge_field_paragraph!
class DocxInsertMergeFieldTool < RubyLLM::Tool
  description "Inserts a new paragraph containing a Sablon merge field " \
              "(e.g. 'investor_kyc.individual?:if', 'investor_kyc.individual?:endIf', " \
              "'=investor_kyc.full_name') immediately before or after an existing " \
              "paragraph. Use this to wrap a block of content in a Sablon " \
              "conditional/loop instead of deleting it — e.g. when a template " \
              "contains two alternate variants of a section (for different " \
              "investor/contributor types) that were never actually made " \
              "conditional, so both render unconditionally and duplicate the " \
              "numbering. The expression must not contain spaces, and must be a " \
              "REAL Sablon operation: '=expr' (value), or expr ending in ':if', " \
              "':elsif', ':elseIf', ':else', ':endIf', ':each(item)', or ':endEach'. " \
              "Sablon has NO ':unless' — to show a block only when a condition is " \
              "false, wrap it with the negated boolean's ':if' (e.g. " \
              "'foo.non_individual?:if' ... ':endIf'), never invent an ':unless' " \
              "operation; this tool will reject it."

  param :part, type: :string, desc: "Part to insert into.", required: true
  param :anchor_index, type: :integer, desc: "Index of the existing paragraph to insert next to.", required: true
  param :position, type: :string, desc: "'before' or 'after' the anchor paragraph.", required: true
  param :expression, type: :string,
                     desc: "Sablon expression, no leading '=' unless it's a value field. " \
                           "Examples: 'investor_kyc.individual?:if', 'investor_kyc.individual?:endIf', " \
                           "'=investor_kyc.full_name'. No ':unless' — see tool description.",
                     required: true
  param :clone_ppr_from, type: :integer,
                         desc: "Optional paragraph index to copy indentation/style from " \
                               "(numbering is always stripped). Defaults to the anchor's own formatting.",
                         required: false

  def initialize(workspace:)
    super()
    @workspace = workspace
  end

  def execute(part: nil, anchor_index: nil, position: nil, expression: nil, clone_ppr_from: nil)
    display_text = "«#{expression}»"
    @workspace.insert_merge_field_paragraph!(
      part, anchor_index,
      position: position, expression: expression, display_text: display_text, clone_ppr_from: clone_ppr_from
    )
    @workspace.record_change("Inserted merge field «#{expression}» #{position} paragraph #{anchor_index} in #{part}")
    "OK. Inserted a merge field paragraph («#{expression}») #{position} paragraph #{anchor_index}. " \
      "Paragraph indices after this point in #{part} have shifted by one — re-run DocxSearchTextTool " \
      "if you need to locate a paragraph you found earlier by index."
  rescue DocxWorkspace::InvalidPart, ArgumentError => e
    "Error: #{e.message}"
  end
end
