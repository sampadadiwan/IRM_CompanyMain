# app/helpers/markdown_helper.rb
module MarkdownHelper
  def markdown_to_html(text)
    renderer = Redcarpet::Render::HTML.new(
      filter_html: true,     # removes raw HTML for safety
      hard_wrap: true        # adds <br> for line breaks
    )

    markdown = Redcarpet::Markdown.new(renderer, {
                                         autolink: true, # automatically link URLs
                                         tables: true, # enable GitHub-style tables
                                         fenced_code_blocks: true,
                                         strikethrough: true,
                                         lax_spacing: true,
                                         space_after_headers: true
                                       })

    markdown.render(text).html_safe
  end
end
