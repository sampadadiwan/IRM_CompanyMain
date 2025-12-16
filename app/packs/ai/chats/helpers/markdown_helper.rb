# app/helpers/markdown_helper.rb
module MarkdownHelper
  # rubocop:disable Rails/OutputSafety
  def markdown_to_html(text)
    return "" if text.blank?

    renderer = Redcarpet::Render::HTML.new(hard_wrap: true)
    markdown = Redcarpet::Markdown.new(
      renderer,
      autolink: true,
      tables: true,
      fenced_code_blocks: true,
      strikethrough: true,
      lax_spacing: true,
      space_after_headers: true
    )

    rendered_html = markdown.render(text.to_s)

    # Use an explicit permit scrubber so attributes like img[src] are not stripped.
    # Also allow specific tags/attributes needed for safe client-side chart rendering.
    scrubber = Rails::Html::PermitScrubber.new
    scrubber.tags = %w[p a strong em br table thead tbody tr th td pre code img div canvas]
    scrubber.attributes = %w[
      href title src alt
      class id width height
      data-controller
      data-chart-renderer-spec-value
      data-chart-renderer-target
    ]

    sanitize(rendered_html, scrubber: scrubber).html_safe
  end
  # rubocop:enable Rails/OutputSafety
end
