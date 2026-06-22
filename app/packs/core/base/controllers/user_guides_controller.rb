class UserGuidesController < ApplicationController
  after_action :verify_authorized
  before_action :force_html_format, only: :show

  GUIDES_ROOT = Rails.root.join("docs/user_guides").freeze

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

      content     = File.read(path)
      lines       = content.split("\n").reject { |l| l.strip.empty? || l.start_with?("#") || l.start_with?("---") }
      description = lines.first&.truncate(120) || "Learn how to use the #{title.downcase} features in IRM."

      { id: id, title: title, group: group, description: description }
    end

    # Group: nil (top-level) first, then named groups alphabetically
    @grouped_guides = @guides.group_by { |g| g[:group] }
                             .sort_by { |group, _| group.nil? ? "" : group }
                             .to_h
    @bread_crumbs = { t('top_menus.user_guides') => nil }
  end

  def show
    authorize :user_guide, :show?

    raw_id    = params[:id].to_s.sub(/\.md$/i, "")
    # Prevent directory traversal
    safe_path = GUIDES_ROOT.join("#{raw_id}.md").cleanpath
    unless safe_path.to_s.start_with?("#{GUIDES_ROOT}/")
      redirect_to user_guides_path, alert: "User guide not found."
      return
    end

    if File.exist?(safe_path)
      content = File.read(safe_path)
      renderer = Redcarpet::Render::HTML.new(hard_wrap: true, filter_html: true, with_toc_data: true)
      markdown = Redcarpet::Markdown.new(renderer, autolink: true, tables: true, fenced_code_blocks: true, lax_spacing: true, space_after_headers: true)
      @html_content = markdown.render(content).html_safe

      parts  = raw_id.split("/")
      @title = parts.last.humanize.titleize.gsub(/ User Guide$/i, '')

      if parts.length > 1
        group_label = parts.first.humanize.titleize
        @bread_crumbs = { t('top_menus.user_guides') => user_guides_path, group_label => nil, @title => nil }
      else
        @bread_crumbs = { t('top_menus.user_guides') => user_guides_path, @title => nil }
      end
    else
      redirect_to user_guides_path, alert: "User guide not found."
    end
  end

  private

  def force_html_format
    request.format = :html
  end
end
