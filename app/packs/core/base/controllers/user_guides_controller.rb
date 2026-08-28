class UserGuidesController < ApplicationController
  # Markdown resolution/rendering is shared with PublicGuidesController, which serves a
  # login-less subset of the same files.
  include WithGuideRendering

  # Website-styled shell instead of the app's Modernize sidebar chrome — shared with
  # PublicGuidesController so both guide surfaces look like the same product.
  layout "guide"

  after_action :verify_authorized
  before_action :force_html_format, only: :show

  def index
    authorize :user_guide, :index?
    skip_policy_scope

    all_files = Dir.glob(GUIDES_ROOT.join("**", "*.md"))

    # Build a flat list with group = subdirectory name (nil for top-level)
    @guides = all_files.map do |path|
      relative = Pathname.new(path).relative_path_from(GUIDES_ROOT).to_s # e.g. "agents/data_quality_agent_user_guide.md"
      id       = relative.sub(/\.md$/, "")                               # e.g. "agents/data_quality_agent_user_guide"
      parts    = id.split("/")
      group    = parts.length > 1 ? parts.first.humanize.titleize : nil
      title    = parts.last.humanize.titleize.gsub(/ User Guide$/i, '')

      description = strip_inline_markdown(first_content_line(path))&.truncate(260) || "Learn how to use the #{title.downcase} features in IRM."

      { id: id, title: title, group: group, description: description }
    end

    # Group: nil (top-level) first, then named groups alphabetically
    @grouped_guides = @guides.group_by { |g| g[:group] }
                             .sort_by { |group, _| group.nil? ? "" : group }
                             .to_h
  end

  def show
    authorize :user_guide, :show?

    raw_id = params[:id].to_s.sub(/\.md$/i, "")
    # resolve_guide_path returns nil for a missing file or any id that escapes GUIDES_ROOT.
    safe_path = resolve_guide_path(raw_id)

    if safe_path.nil?
      redirect_to user_guides_path, alert: "User guide not found."
      return
    end

    @html_content = render_guide_markdown(safe_path)

    parts  = raw_id.split("/")
    @title = guide_title(raw_id)
    @lede  = strip_inline_markdown(first_content_line(safe_path)) || "A guide to #{@title.downcase}."
    @group_label = parts.first.humanize.titleize if parts.length > 1
    @hero_tint = hero_tint_for(raw_id, @group_label)
  end

  private

  def force_html_format
    request.format = :html
  end
end
