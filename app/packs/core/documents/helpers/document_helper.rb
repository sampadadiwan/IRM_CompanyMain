module DocumentHelper
  FIXNUM_MAX = ((2**((0.size * 8) - 2)) - 1)

  def download_xl_link(data_source)
    uri = URI.parse(data_source)
    query = Rack::Utils.parse_query(uri.query)
    uri.query = Rack::Utils.build_query(query)
    uri.to_s.gsub(".json", ".xlsx")
  end

  def uploaded_file_name(file)
    file.metadata['filename'] if file.metadata
  end

  # Where a link on a document's name should go: the stored file itself, opened in the browser,
  # falling back to the document page.
  #
  # Same rule as documents/_card_view.html.erb. `orignal` is what says the file may be served
  # as-is, and not_generated_or_approved keeps a generated-but-unapproved draft behind the
  # document page, where the approval state is visible - a direct link would hand out a file
  # nobody has signed off yet. Everything else goes to document_path, which authorizes through
  # DocumentPolicy#show? rather than handing out a signed URL.
  #
  # Returns nil when there is no file to point at, so callers can render plain text instead of
  # a link that 404s.
  def document_file_url(document)
    return nil if document.blank? || document.file.blank?

    if document.orignal && policy(document).not_generated_or_approved
      document.file.url(response_content_disposition: "inline; filename=#{document.name_with_extension}")
    else
      document_path(document)
    end
  rescue StandardError => e
    Rails.logger.warn("document_file_url failed for document #{document&.id}: #{e.message}")
    nil
  end

  # This method returns all the folders to be displayed in the tree view
  def get_tree_view_folders(params, current_user, entity, documents)
    entity_id = params[:entity_id].present? ? params[:entity_id].to_i : current_user.entity_id

    # If the user is from the same company show him all the folders
    # Changed: Added .includes(:nda_config) to all four query paths below.
    # Why: The folder tree now renders an NDA lock icon via folder.nda_required? — without
    # eager-loading, each folder triggers a separate query for its nda_config (N+1).
    if belongs_to_entity_id?(current_user, entity_id) && current_user.has_cached_role?(:company_admin)
      folders = if params[:folder_id].present?
                  Folder.find(params[:folder_id]).subtree.includes(:nda_config).order(:name).arrange
                else
                  entity.root_folder.subtree.includes(:nda_config).order(:name).arrange
                end
    else
      # If the user is NOT from the same company show him only the folders for the documents he has access to

      aids = with_ancestor_ids(documents)

      if params[:folder_id].present?
        # We need to show only the descendants of parent, but we also want to show only those folder for which the user has documents that he can see.
        parent = Folder.find(params[:folder_id])
        # descendant_ids = parent.descendant_ids
        # descendant_ids << parent.id
        # folders = Folder.where(id: descendant_ids).where(id: aids).order(:name).arrange
        folders = Folder.where(level: parent.level..).where(id: aids).includes(:nda_config).order(:name).arrange
      else
        folders = Folder.where(id: aids).includes(:nda_config).order(:name).arrange
      end
    end

    folders
  end

  # Journey records whose notices an "approve_notices" list can be filtered to, by the ransack
  # attribute the call's / distribution's "View Generated Notices To Approve" link filters on
  APPROVAL_HINT_RECORDS = { "capital_call_id" => "CapitalCall", "capital_distribution_id" => "CapitalDistribution" }.freeze

  # The call or distribution an approve_notices list is filtered to, or nil. Read from the ransack
  # search the list itself ran, so both the flat (q[capital_call_id_eq]) and the grouped
  # (RansackQueryBuilder.multiple) link shapes work. The id is looked up and authorized — nothing from
  # the URL is printed as-is.
  def approval_hint_record(search)
    return if search.blank?

    APPROVAL_HINT_RECORDS.each do |attr, klass|
      # Only a plain "<attr> = id" condition identifies one record
      condition = search.base.conditions.find { |c| c.predicate.name == "eq" && c.attributes.map { |a| a.name.to_s } == [attr] }
      next unless condition

      record = klass.constantize.find_by(id: condition.values.first&.value)
      return record if record && policy(record).show?
    end
    nil
  end

  # True while any generated notice of the call / distribution is unapproved. exists?, not a count:
  # documents is a large table (CLAUDE.md).
  def notices_awaiting_approval?(record)
    owners = record.is_a?(CapitalCall) ? record.capital_remittances : record.capital_distribution_payments
    Document.not_templates.exists?(owner_type: owners.klass.name, owner_id: owners.select(:id), owner_tag: "Generated", approved: false)
  end

  def with_ancestor_ids(documents)
    ids = documents.joins(:folder).pluck("documents.folder_id, folders.ancestry")
    ids.map { |p| p[1] ? (p[1].split("/") << p[0]) : [p[0]] }.flatten.map(&:to_i).uniq
  end

  # rubocop:disable Rails/OutputSafety
  def render_markdown(text)
    return "" if text.blank?

    renderer = Redcarpet::Render::HTML.new(
      filter_html: true,
      hard_wrap: true,
      link_attributes: { rel: 'nofollow', target: '_blank' }
    )
    markdown = Redcarpet::Markdown.new(
      renderer,
      autolink: true,
      tables: true,
      fenced_code_blocks: true,
      strikethrough: true,
      superscript: true
    )
    html = markdown.render(text)
    sanitize(html).html_safe
  end
  # rubocop:enable Rails/OutputSafety
end
