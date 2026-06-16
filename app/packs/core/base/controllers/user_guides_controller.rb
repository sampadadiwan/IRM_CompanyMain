class UserGuidesController < ApplicationController
  after_action :verify_authorized

  def index
    authorize :user_guide, :index?
    skip_policy_scope
    @guides = Rails.root.glob("docs/user_guides/*.md").map do |path|
      id = File.basename(path, ".md")
      title = id.humanize.titleize.gsub(/ User Guide$/i, '')

      content = File.read(path)
      # Extract first paragraph (skip title and empty lines)
      lines = content.split("\n").reject { |l| l.strip.empty? || l.start_with?("#") || l.start_with?("---") }
      description = lines.first&.truncate(120) || "Learn how to use the #{title.downcase} features in IRM."

      { id: id, title: title, description: description }
    end.sort_by { |g| g[:title] }
    @bread_crumbs = { t('top_menus.user_guides') => nil }
  end

  def show
    authorize :user_guide, :show?
    @guide_id = params[:id]
    @guide_file = Rails.root.join("docs/user_guides", "#{@guide_id}.md")

    if File.exist?(@guide_file)
      content = File.read(@guide_file)
      renderer = Redcarpet::Render::HTML.new(hard_wrap: true, filter_html: true, with_toc_data: true)
      markdown = Redcarpet::Markdown.new(renderer, autolink: true, tables: true, fenced_code_blocks: true, lax_spacing: true, space_after_headers: true)
      @html_content = markdown.render(content).html_safe
      @title = @guide_id.humanize.titleize.gsub(/ User Guide$/i, '')
      @bread_crumbs = { t('top_menus.user_guides') => user_guides_path, @title => nil }
    else
      redirect_to user_guides_path, alert: "User guide not found."
    end
  end
end
