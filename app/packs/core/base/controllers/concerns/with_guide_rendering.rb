# Shared Markdown resolution and rendering for the Markdown trees under docs/.
#
# Three controllers render Markdown off disk: the signed-in guide browser
# (UserGuidesController), the public, login-less guide pages
# (PublicGuidesController) and the staff-only internal docs viewer
# (InternalDocsController). The renderer options and the directory-traversal
# guard live here rather than being duplicated — a divergence in either would be
# a security or a formatting bug depending on which copy drifted.
module WithGuideRendering
  extend ActiveSupport::Concern

  # Root of the Markdown sources for the guide controllers. Every path resolved
  # by this concern is verified to sit underneath #guides_root, which defaults
  # to this constant.
  GUIDES_ROOT = Rails.root.join("docs/user_guides").freeze

  private

  # The directory every resolved path must sit inside. Overridable so a
  # controller serving a different tree (InternalDocsController serves all of
  # docs/) reuses this traversal guard instead of writing a second one.
  #
  # @return [Pathname]
  def guides_root
    GUIDES_ROOT
  end

  # Resolves a guide id ("kpi_upload_user_guide", "agents/esign_monitor_agent_user_guide")
  # to an on-disk path, refusing anything that escapes #guides_root.
  #
  # @param raw_id [String] guide id from the URL, with or without a .md suffix
  # @return [Pathname, nil] the readable guide path, or nil if missing/out of bounds
  def resolve_guide_path(raw_id)
    id = raw_id.to_s.sub(/\.md$/i, "")
    # cleanpath collapses any ".." segments so the start_with? check below cannot
    # be walked past with a crafted id.
    path = guides_root.join("#{id}.md").cleanpath
    return nil unless path.to_s.start_with?("#{guides_root}/")
    return nil unless File.exist?(path)

    path
  end

  # @param path [Pathname] a path already vetted by resolve_guide_path
  # @return [ActiveSupport::SafeBuffer] rendered HTML for the .ai-md container
  def render_guide_markdown(path)
    renderer = Redcarpet::Render::HTML.new(hard_wrap: true, filter_html: true, with_toc_data: true)
    markdown = Redcarpet::Markdown.new(renderer, autolink: true, tables: true,
                                                 fenced_code_blocks: true, lax_spacing: true,
                                                 space_after_headers: true)
    markdown.render(File.read(path)).html_safe
  end

  # Human-readable title for a guide id — the last path segment, titleised, with
  # the redundant "User Guide" suffix trimmed.
  #
  # @param raw_id [String] guide id from the URL
  # @return [String]
  def guide_title(raw_id)
    raw_id.to_s.sub(/\.md$/i, "").split("/").last.humanize.titleize.gsub(/ User Guide$/i, "")
  end
end
