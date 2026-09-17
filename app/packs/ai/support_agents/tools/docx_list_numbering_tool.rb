# frozen_string_literal: true

# RubyLLM tool: dumps numId -> abstractNumId + lvlOverride/startOverride
# mappings from numbering.xml — needed to tell whether two paragraphs sharing
# a visible "5.2.9"-style label are actually the same list or two independent
# lists that coincidentally reach the same displayed number.
#
# @see DocxWorkspace#list_numbering
class DocxListNumberingTool < RubyLLM::Tool
  description "Lists numbering definitions from word/numbering.xml: each numId's " \
              "abstractNumId and any lvlOverride/startOverride values. Use this " \
              "to check whether two paragraphs displaying the same clause number " \
              "belong to the same list (same numId) or two independently-counting " \
              "lists that happen to collide (different numId, same abstractNumId)."

  param :num_id, type: :string,
                 desc: "Restrict to one numId. Omit to list all numbering definitions.",
                 required: false

  def initialize(workspace:)
    super()
    @workspace = workspace
  end

  def execute(num_id: nil)
    rows = @workspace.list_numbering(num_id: num_id)
    return "No numbering definitions found#{" for numId=#{num_id}" if num_id.present?}." if rows.empty?

    rows.map do |r|
      overrides = r[:lvl_overrides].map { |o| "ilvl=#{o[:ilvl]} startOverride=#{o[:start_override]}" }.join(", ")
      "numId=#{r[:num_id]} abstractNumId=#{r[:abstract_num_id]}#{" [#{overrides}]" if overrides.present?}"
    end.join("\n")
  end
end
