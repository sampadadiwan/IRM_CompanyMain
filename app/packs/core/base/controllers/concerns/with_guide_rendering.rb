# Shared Markdown rendering for the user guides in docs/user_guides.
#
# Both the signed-in guide browser (UserGuidesController) and the public,
# login-less guide pages (PublicGuidesController) render the same source files,
# so the renderer options and the directory-traversal guard live here rather
# than being duplicated — a divergence in either would be a security or a
# formatting bug depending on which copy drifted.
module WithGuideRendering
  extend ActiveSupport::Concern

  # Root of the Markdown sources. Every path resolved by this concern is
  # verified to sit underneath it.
  GUIDES_ROOT = Rails.root.join("docs/user_guides").freeze

  private

  # Resolves a guide id ("kpi_upload_user_guide", "agents/esign_monitor_agent_user_guide")
  # to an on-disk path, refusing anything that escapes GUIDES_ROOT.
  #
  # @param raw_id [String] guide id from the URL, with or without a .md suffix
  # @return [Pathname, nil] the readable guide path, or nil if missing/out of bounds
  def resolve_guide_path(raw_id)
    id = raw_id.to_s.sub(/\.md$/i, "")
    # cleanpath collapses any ".." segments so the start_with? check below cannot
    # be walked past with a crafted id.
    path = GUIDES_ROOT.join("#{id}.md").cleanpath
    return nil unless path.to_s.start_with?("#{GUIDES_ROOT}/")
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
