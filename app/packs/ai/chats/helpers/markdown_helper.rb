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
    scrubber.tags = %w[
      h1 h2 h3 h4 h5 h6
      p a strong em br
      ul ol li
      table thead tbody tr th td
      pre code blockquote
      img div canvas
    ]
    scrubber.attributes = %w[
      href title src alt
      class id width height
      data-controller
      data-chart-renderer-spec-value
      data-chart-renderer-target
    ]

    ActionController::Base.helpers.sanitize(rendered_html, scrubber: scrubber).html_safe
  end

  def markdown_with_charts_and_unused(md, charts)
    return { html: "", unused_charts: [] } if md.blank?

    # Render markdown first (so underscores don’t get mangled inside placeholders)
    html = markdown_to_html(md).to_s

    used_ids = []

    Array(charts).each do |chart|
      id = chart["id"]
      next if id.blank?

      placeholder = "{{chart:#{id}}}"

      # If placeholder is present in the rendered HTML, replace it with a canvas wrapper
      next unless html.include?(placeholder)

      type  = chart.dig("config", "type").to_s
      klass = "ai-chart"
      klass += " ai-chart--#{type}" if type.present?

      html = html.gsub(
        placeholder,
        %(<div class="#{klass}"><canvas id="chart-#{id}"></canvas></div>)
      )

      used_ids << id
    end

    unused = Array(charts).reject { |c| used_ids.include?(c["id"]) }

    { html: html.html_safe, unused_charts: unused }
  end

  # rubocop:enable Rails/OutputSafety
end
