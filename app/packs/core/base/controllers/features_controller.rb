class FeaturesController < ApplicationController
  after_action :verify_authorized
  before_action :force_html_format, only: :show

  FEATURES_ROOT = Rails.root.join("docs/features").freeze

  def index
    authorize :feature, :index?
    skip_policy_scope

    all_files = Dir.glob(FEATURES_ROOT.join("**", "*.md")).sort

    # Build a flat list with group = subdirectory name (nil for top-level)
    @features = all_files.map do |path|
      relative = Pathname.new(path).relative_path_from(FEATURES_ROOT).to_s  # e.g. "us_gtm/closing_room.md"
      id       = relative.sub(/\.md$/, "")                                  # e.g. "us_gtm/closing_room"
      parts    = id.split("/")
      group    = parts.length > 1 ? parts.first.humanize.titleize : nil
      title    = parts.last.humanize.titleize

      content     = File.read(path)
      lines       = content.split("\n").reject { |l| l.strip.empty? || l.start_with?("#") || l.start_with?("---") }
      description = lines.first&.truncate(120) || "Feature documentation for #{title.downcase}."

      { id: id, title: title, group: group, description: description }
    end

    # Group: nil (top-level) first, then named groups alphabetically
    @grouped_features = @features.group_by { |f| f[:group] }
                                  .sort_by { |group, _| group.nil? ? "" : group }
                                  .to_h

    @bread_crumbs = { t("top_menus.features") => nil }
  end

  def show
    authorize :feature, :show?

    raw_id      = params[:id].to_s.sub(/\.md$/i, "")
    # Prevent directory traversal
    safe_path   = FEATURES_ROOT.join("#{raw_id}.md").cleanpath
    unless safe_path.to_s.start_with?(FEATURES_ROOT.to_s + "/")
      redirect_to features_path, alert: "Feature document not found."
      return
    end

    if File.exist?(safe_path)
      content  = File.read(safe_path)
      renderer = Redcarpet::Render::HTML.new(hard_wrap: true, filter_html: true, with_toc_data: true)
      markdown = Redcarpet::Markdown.new(renderer, autolink: true, tables: true, fenced_code_blocks: true, lax_spacing: true, space_after_headers: true)
      @html_content = markdown.render(content).html_safe

      parts  = raw_id.split("/")
      @title = parts.last.humanize.titleize

      if parts.length > 1
        group_label = parts.first.humanize.titleize
        @bread_crumbs = { t("top_menus.features") => features_path, group_label => nil, @title => nil }
      else
        @bread_crumbs = { t("top_menus.features") => features_path, @title => nil }
      end
    else
      redirect_to features_path, alert: "Feature document not found."
    end
  end

  private

  def force_html_format
    request.format = :html
  end
end
