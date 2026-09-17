# frozen_string_literal: true

# RubyLLM tool: renders the CURRENT (possibly mid-edit) state of the document
# to PDF via headless LibreOffice and returns page-layout text — the
# Act -> Observe step of the loop. This is how a numbering/pagination fix gets
# verified without a vision-capable model: the same libreoffice --convert-to
# pdf + pdftotext -layout technique used to diagnose and confirm the fix for
# Individual.docx by hand.
#
# @see DocxWorkspace#render_preview!
class DocxRenderPreviewTool < RubyLLM::Tool
  description "Renders the document's CURRENT state (including any edits made " \
              "so far this run) to PDF and returns the extracted page text plus " \
              "total page count. Use this after making edits to verify they had " \
              "the intended effect — e.g. confirm a clause number no longer " \
              "duplicates, or that a blank-page gap is gone — before finishing. " \
              "This can take up to a minute; don't call it after every single " \
              "small edit, batch related edits first."

  param :page_query, type: :string,
                     desc: "Optional text to search for in the rendered output, to avoid " \
                           "returning the entire (possibly long) document text.",
                     required: false

  def initialize(workspace:)
    super()
    @workspace = workspace
  end

  def execute(page_query: nil)
    result = @workspace.render_preview!
    return "Render failed: #{result[:error]}" unless result[:success]

    text = result[:text].to_s
    header = "Rendered OK. #{result[:page_count]} page(s)."
    header += blank_page_warning(result[:blank_page_hints])

    return header if page_query.blank?

    pages = text.split("\f")
    hits = pages.each_with_index.select { |page, _| page.include?(page_query) }
    return "#{header}\nNo page contains \"#{page_query}\"." if hits.empty?

    matched = hits.first(3).map { |page, idx| "--- page #{idx + 1} ---\n#{page.strip}" }.join("\n\n")
    "#{header}\n#{matched}"
  end

  private

  def blank_page_warning(hints)
    return "" if hints.blank?

    details = hints.map { |h| "page #{h[:page]} (#{h[:chars]} chars; next page starts \"#{h[:next_page_starts_with]}\")" }.join("; ")
    "\n⚠ Nearly-blank page(s) detected: #{details}. This is the signature of a paragraph " \
      "style's keepNext chaining several consecutive same-style paragraphs (e.g. a Heading4-" \
      "style sub-clause list) into one unbreakable block that doesn't fit the remaining page " \
      "space, so LibreOffice pushes the WHOLE block to the next page. Use DocxInspectParagraphTool " \
      "on the first paragraph(s) of the page right after the gap to find their style, then " \
      "DocxSetStylePropertyTool(style_id: <that style>, property: 'keepNext', enabled: false) — " \
      "don't just delete/shorten content to make it fit."
  end
end
