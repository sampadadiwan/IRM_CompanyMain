# frozen_string_literal: true

# RubyLLM tool: toggles a boolean paragraph-property flag (e.g. <w:keepNext/>,
# <w:keepLines/>, <w:pageBreakBefore/>) on a named style in styles.xml. This is
# the fix for pagination bugs caused by a style built for headings (which
# carries keepNext) being repurposed purely for list-item indentation —
# exactly what produced the Individual.docx blank-page-after-heading bug.
#
# @see DocxWorkspace#set_style_property!
class DocxSetStylePropertyTool < RubyLLM::Tool
  description "Enables or disables a boolean paragraph-property flag on a named " \
              "style in styles.xml, e.g. 'keepNext', 'keepLines', 'pageBreakBefore', " \
              "'widowControl'. Use this when a style is forcing unwanted pagination " \
              "— e.g. multiple consecutive paragraphs using a heading style that " \
              "carries keepNext get forced onto the same page as a block, stranding " \
              "earlier content with a large blank gap when they don't all fit."

  param :style_id, type: :string, desc: "The w:styleId to modify, e.g. 'Heading4'.", required: true
  param :property, type: :string, desc: "The property name, e.g. 'keepNext'.", required: true
  param :enabled, type: :boolean, desc: "true to add the flag, false to remove it.", required: true

  def initialize(workspace:)
    super()
    @workspace = workspace
  end

  def execute(style_id: nil, property: nil, enabled: nil)
    @workspace.set_style_property!(style_id: style_id, property: property, enabled: enabled)
    @workspace.record_change("Style '#{style_id}': #{property} #{enabled ? 'enabled' : 'removed'}")
    "OK. Style '#{style_id}' #{property} is now #{enabled ? 'enabled' : 'removed'}."
  rescue DocxWorkspace::InvalidPart, ArgumentError => e
    "Error: #{e.message}"
  end
end
