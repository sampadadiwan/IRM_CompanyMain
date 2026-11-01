# L13 — renders GP-authored CiWidget content without ever echoing stored HTML as-is. Widgets are shown
# to LPs (investment opportunity previews) on the app's own origin, so a script in a widget would run in
# the LP's session. docs/security/security_review_2026_10.md (L13)
# Tests L13-X1..X5, L13-H1, L13-H2 — features/security/ci_widget_embeds.feature
module CiWidgetHelper
  # The tags the rich-text editor produces for widget text (Trix: div, br, strong, em, lists, links,
  # headings, quotes, code). No style attribute, so no CSS from the stored text reaches the page.
  CI_WIDGET_TAGS = %w[div p br span strong b em i u s del ul ol li a h1 h2 h3 h4 h5 h6 blockquote pre code].freeze
  CI_WIDGET_ATTRIBUTES = %w[href title].freeze

  # Rich text (details / details_top) through the sanitizer: script, event handlers, iframes and
  # javascript: links are dropped, the formatting tags above are kept (L13-X3, L13-H2)
  def ci_widget_rich_text(html)
    return "" if html.blank?

    sanitize(html, tags: CI_WIDGET_TAGS, attributes: CI_WIDGET_ATTRIBUTES)
  end

  # The video embed, rebuilt from the parsed player URL: a sandboxed, lazy iframe. A stored value that
  # is not one allowed player iframe renders nothing (L13-X1, L13-X4, L13-H1)
  def ci_widget_embed(widget)
    # Only the validated src is used; the stored attributes and any surrounding markup are discarded
    src = widget.embed_src
    return "" unless src

    # allow-scripts + allow-same-origin let the player run on its own (youtube) origin; it cannot reach
    # the app's origin from inside the sandbox, nor navigate the top window
    tag.iframe(src:, title: widget.title, loading: "lazy",
               sandbox: "allow-scripts allow-same-origin allow-presentation allow-popups",
               allow: "accelerometer; encrypted-media; gyroscope; picture-in-picture; fullscreen",
               referrerpolicy: "strict-origin-when-cross-origin", allowfullscreen: true,
               class: "w-100 h-100 border-0")
  end
end
