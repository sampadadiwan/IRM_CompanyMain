class ReleaseNotesController < ApplicationController
  after_action :verify_authorized

  def index
    authorize :release_note, :index?
    skip_policy_scope
    @notes = Dir.glob(Rails.root.join("docs/release_notes", "*.md")).map do |path|
      id = File.basename(path, ".md")
      title = id.humanize.titleize
      mtime = File.mtime(path)

      content = File.read(path)
      # Prefer h3 headings (individual features) for a richer card preview
      features = content.scan(/^###\s+(.+)/).flatten.map(&:strip)
      # Fall back to h2 headings, then first prose line
      features = content.scan(/^##\s+(.+)/).flatten.map(&:strip) if features.empty?
      fallback = content.split("\n")
                        .reject { |l| l.strip.empty? || l.match?(/\A[#]{1,6}\s/) || l.start_with?("---") || l.match?(/\A\*\*Released/) }
                        .first
                        .then { |l| l&.gsub(/[*_`#>|]/, '')&.strip }
      description = features.any? ? features.join(" · ").truncate(600) : (fallback&.truncate(600) || "Release notes for #{title}.")

      { id: id, title: title, description: description, date: mtime }
    end.sort_by { |n| n[:date] }.reverse
    @bread_crumbs = { t('top_menus.release_notes') => nil }
  end

  def show
    authorize :release_note, :show?
    @note_id = params[:id]
    @note_file = Rails.root.join("docs/release_notes", "#{@note_id}.md")

    if File.exist?(@note_file)
      content = File.read(@note_file)
      renderer = Redcarpet::Render::HTML.new(hard_wrap: true, filter_html: true, with_toc_data: true)
      markdown = Redcarpet::Markdown.new(renderer, autolink: true, tables: true, fenced_code_blocks: true, lax_spacing: true, space_after_headers: true)
      @html_content = markdown.render(content).html_safe
      @title = @note_id.humanize.titleize
      @bread_crumbs = { t('top_menus.release_notes') => release_notes_path, @title => nil }
    else
      redirect_to release_notes_path, alert: "Release note not found."
    end
  end
end
