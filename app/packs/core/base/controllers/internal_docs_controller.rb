# Private, in-app browser for CapHive's marketing and commercial documentation.
#
# Visible only to CapHive staff — not to customers, and not to the public
# internet. This app has real customer logins (GP and LP users), so
# InternalDocPolicy is the only boundary between a customer account and
# CapHive's pricing bands, GTM playbook and competitive analysis. Treat a gap
# here as a data-exposure bug, not a UX bug.
#
# Design note: this deliberately mirrors UserGuidesController and reuses its
# WithGuideRendering concern rather than copying the traversal guard. A drifted
# copy of that guard on the tree holding security reviews and incident RCAs is
# precisely the bug to avoid. See docs/technical/internal_docs_viewer.md.
class InternalDocsController < ApplicationController
  include WithGuideRendering

  after_action :verify_authorized
  before_action :force_html_format, only: :show

  # Root of the whole documentation tree. Only the SECTIONS below are reachable
  # from it — see #section_allowed?.
  DOCS_ROOT = Rails.root.join("docs").freeze

  # Only these trees are browsable, and this is both the navigation structure
  # and a security boundary. Everything else under docs/ — technical/,
  # security/, ai/, dr_review/, incidents/, troubleshooting/ and the rest — is
  # unreachable even to a staff user. Adding a directory here is a deliberate
  # act, not a convenience.
  #
  # "Strategy" carries docs/features/: the parent strategy document
  # docs/features/us_gtm.md (ICP, personas, pricing framework, sales playbook)
  # lives there and every doc under docs/marketing/ links to it by relative
  # path, so excluding it would leave the marketing set full of dead links to
  # its most important reference.
  SECTIONS = {
    "Marketing" => %w[marketing],
    "Strategy"  => %w[features]
  }.freeze

  # Flattened whitelist of first path segments, for the per-request check.
  ALLOWED_DIRS = SECTIONS.values.flatten.freeze

  def index
    authorize :internal_doc, :index?
    skip_policy_scope

    # { "Marketing" => { nil => [...], "Linkedin Posts" => [...] }, "Strategy" => {...} }
    @sections = SECTIONS.each_with_object({}) do |(label, dirs), acc|
      docs = dirs.flat_map { |dir| docs_in(dir) }
      next if docs.empty?

      acc[label] = docs.group_by { |doc| doc[:group] }
                       .sort_by { |group, _| group.nil? ? "" : group }
                       .to_h
    end

    @doc_count    = @sections.values.sum { |groups| groups.values.sum(&:size) }
    @bread_crumbs = { t("top_menus.internal_docs") => nil }
  end

  def show
    authorize :internal_doc, :show?

    # Clean the id ONCE, up front, and use the cleaned form for everything after.
    # "marketing/../technical/x" has a first segment of "marketing" but resolves
    # into technical/, so any code reading a path segment off the raw string —
    # the whitelist check and the breadcrumb label alike — would be reading a
    # segment the file never came from.
    doc_id = Pathname.new(params[:id].to_s.sub(/\.md$/i, "")).cleanpath.to_s

    # Whitelist first, before any file is touched: an id outside the browsable
    # sections is a not-found regardless of whether the file exists, so this
    # route can never be walked across the rest of docs/.
    unless section_allowed?(doc_id)
      redirect_to internal_docs_path, alert: "Document not found."
      return
    end

    # Second layer: resolve_guide_path returns nil for a missing file or any id
    # that escapes DOCS_ROOT.
    safe_path = resolve_guide_path(doc_id)

    if safe_path.nil?
      redirect_to internal_docs_path, alert: "Document not found."
      return
    end

    @html_content = render_guide_markdown(safe_path)
    @title        = guide_title(doc_id, safe_path)

    # Never nil: doc_id is cleaned, and section_allowed? has already passed on it.
    section_label = section_for(doc_id.split("/").first)
    @bread_crumbs = { t("top_menus.internal_docs") => internal_docs_path,
                      section_label => nil,
                      @title => nil }
  end

  private

  # Serve the whole docs tree, not just docs/user_guides — the SECTIONS
  # whitelist, not the root, is what narrows this down.
  def guides_root
    DOCS_ROOT
  end

  # Is the first path segment of this id one of the browsable sections?
  #
  # Expects an id already collapsed by cleanpath (see #show) — a raw id could
  # still carry ".." segments and would be trivially bypassable.
  #
  # @param doc_id [String] cleaned doc id, without the .md suffix
  # @return [Boolean]
  def section_allowed?(doc_id)
    ALLOWED_DIRS.include?(doc_id.to_s.split("/").first)
  end

  # Section label ("Marketing") for a top-level directory name ("marketing").
  #
  # @param dir [String]
  # @return [String, nil]
  def section_for(dir)
    SECTIONS.find { |_label, dirs| dirs.include?(dir) }&.first
  end

  # Every Markdown file under one whitelisted directory, as index rows.
  #
  # @param dir [String] a top-level directory name from ALLOWED_DIRS
  # @return [Array<Hash>]
  def docs_in(dir)
    Dir.glob(DOCS_ROOT.join(dir, "**", "*.md")).sort.map do |path|
      relative = Pathname.new(path).relative_path_from(DOCS_ROOT).to_s # "marketing/linkedin_posts/foo.md"
      id       = relative.sub(/\.md$/, "")                            # "marketing/linkedin_posts/foo"
      parts    = id.split("/")
      # Group by the subdirectory below the section root; nil for files sitting
      # directly in it, which sort first in the index.
      group    = parts.length > 2 ? parts[1..-2].join("/").humanize.titleize : nil
      # guide_title, not a local titleize: show uses it too, and it trims a
      # trailing "User Guide". Titling them differently here would make a card
      # and the page it links to disagree about the document's name.
      title    = guide_title(id, path)

      { id: id, title: title, group: group, description: description_for(path, title) }
    end
  end

  # First line of prose in the document, for the index card blurb — skipping
  # blank lines, headings and YAML front-matter fences.
  #
  # Streamed line by line rather than File.read: the index globs every document
  # in both sections and only ever needs the first prose line of each, so
  # slurping them whole would read megabytes per page view to throw nearly all
  # of it away. The lazy chain stops at the first line that qualifies.
  #
  # @param path [String] absolute path to the Markdown file
  # @param title [String] fallback title, used when the document has no prose
  # @return [String]
  def description_for(path, title)
    first_prose_line = File.foreach(path).lazy.map(&:chomp).reject do |line|
      line.strip.empty? || line.start_with?("#") || line.start_with?("---")
    end.first

    first_prose_line&.truncate(120) || "Internal documentation for #{title.downcase}."
  end

  # Doc ids read naturally with no extension; without this a trailing dot in an
  # id would be parsed as a format and blow up template lookup.
  def force_html_format
    request.format = :html
  end
end
