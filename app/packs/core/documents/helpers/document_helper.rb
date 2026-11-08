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

  # [Tabler icon, Bootstrap text colour, label] for a document's file type, read from the stored file's
  # mime type (Shrine metadata on the row - no query, no download)
  def document_file_type(document)
    mime = document.file&.mime_type.to_s
    if mime.include?("pdf") then %w[ti-file-type-pdf text-danger PDF]
    elsif mime.include?("spreadsheet") || mime.include?("excel") || mime.include?("csv") then %w[ti-file-type-xls text-success Spreadsheet]
    elsif mime.include?("word") then %w[ti-file-type-doc text-info Word]
    elsif document.ppt? then %w[ti-file-type-ppt text-warning Presentation]
    elsif mime.include?("video") then %w[ti-video text-secondary Video]
    elsif mime.include?("image") then %w[ti-photo text-secondary Image]
    else %w[ti-file text-secondary File]
    end
  end

  # The file-type icon shown before a document's name (list rows, show page header)
  def document_file_icon(document)
    icon, colour, label = document_file_type(document)
    tag.i(class: "ti #{icon} #{colour}", 'aria-label': label, data: { bs_title: label })
  end

  # "PDF · 214 KB" for the show page's File field; size from the Shrine metadata
  def document_file_summary(document)
    size = document.file&.metadata&.dig("size")
    [document_file_type(document).last, (number_to_human_size(size) if size)].compact.join(" · ")
  end

  # Status badges for a document: approval (generated docs only) and eSign state. Used by the list's
  # Status column and the show page header, so both say the same thing.
  def document_status_badges(document)
    badges = []
    if document.subject_to_approval?
      # Generated docs stay hidden from investors until approved (DocumentPolicy#not_generated_or_approved)
      badges << if document.approved
                  tag.span(safe_join([tag.i(class: "ti ti-circle-check"), " Approved"]), class: "badge bg-success-subtle text-success",
                                                                                         data: { bs_title: "Approved - investors with access can see and download it" })
                else
                  tag.span(safe_join([tag.i(class: "ti ti-clock"), " Pending Approval"]), class: "badge bg-warning-subtle text-warning",
                                                                                          data: { bs_title: "Generated from a template - investors cannot see it until an approver approves it" })
                end
    end
    # eSign state for a document sent (or to be sent) for signature - not for a template, whose
    # signers only describe the documents generated from it
    if document.signature_enabled && !document.template && document.esign_status.present?
      colour = document.esign_status_badge
      badges << tag.span(safe_join([tag.i(class: "ti ti-signature"), " eSign: #{document.esign_status.titleize}"]),
                         class: "badge bg-#{colour}-subtle text-#{colour}",
                         data: { bs_title: "Where the eSignature stands - see the document's Signatures tab for each signer" })
    end
    safe_join(badges, " ")
  end

  # Tags already used on documents in the folder this document goes into, for the form's "Used in this
  # folder" chips. Read from that one folder (folder_id index) rather than the whole firm - documents is
  # a very large table. Only for the firm's own users; at most 20, alphabetical.
  def document_tag_suggestions(document)
    # Fund-side users only: an LP uploading to a fund's record must not see the fund's tag names
    return [] unless document.entity_id.present? && document.entity_id == current_user&.entity_id

    # The folder picked (folder upload), else the owner's documents folder (an owner's Documents tab)
    folder_id = document.folder_id || (document.owner.document_folder_id if document.owner.respond_to?(:document_folder_id))
    return [] if folder_id.blank?

    # folder_id can come from the request - only read a folder this user may see (a private folder's
    # tag names stay hidden from colleagues without access)
    folder = Folder.find_by(id: folder_id)
    return [] unless folder && policy(folder).show?

    # This document's own tags, so they are not offered back
    own_tags = document.tag_list.to_s.split(",").map { |tag| tag.strip.downcase }

    # Distinct values in SQL (unscope(:order): MySQL rejects DISTINCT with an ORDER BY on another column),
    # capped; each value is itself a comma-separated list, so split and dedup the few that come back
    Document.where(folder_id: folder.id).where.not(tag_list: [nil, ""]).unscope(:order).distinct.limit(200).pluck(:tag_list)
            .flat_map { |list| list.split(",") }.map(&:strip).compact_blank
            .uniq(&:downcase)
            .reject { |tag| own_tags.include?(tag.downcase) } # already on this document - nothing to add
            .sort_by(&:downcase).first(20)
  end

  # data-* for the document show page's Approve / UnApprove buttons: the confirm#popup modal with
  # "Immediate Actions" cards saying what the click changes, built with the shared card layout
  # (DocChecksHelper#doc_check_action_summary, same classes as the KYC Request Updates popup).
  def document_approval_confirm_data(document, approve:)
    # Investor visibility: DocumentPolicy#not_generated_or_approved hides unapproved generated docs
    cards = if approve
              [["green", "ti-eye", "Investors can see it",
                "Investors with access to this document can view and download it."]]
            else
              [["amber", "ti-eye-off", "Hidden from investors",
                "Investors can no longer view or download it until it is approved again."]]
            end

    # Notices count towards their call's / distribution's journey
    # (DocumentsController#evaluate_journey_if_notice_approved / _unapproved). Only said when that
    # record has a live journey - the same instance WorkflowEvaluator.for picks; otherwise a no-op.
    journey_record = document.notice_journey_record
    if journey_record && journey_record.workflow_instances.where(evaluated: true).where.not(status: :archived).exists?
      what = journey_record.is_a?(CapitalDistribution) ? "distribution" : "capital call"
      cards << ["blue", "ti-route", "Journey re-checked",
                approve ? "The #{what}'s journey counts this notice as approved and moves on if nothing else is pending." : "The #{what}'s journey goes back to waiting for its notices to be approved."]
    end

    # Either way it can be reversed by an approver
    cards << ["grey", "ti-arrow-back-up", "Can be undone",
              approve ? "An approver can UnApprove it later." : "An approver can Approve it again later."]

    action = approve ? "Approve" : "UnApprove"
    { action: "click->confirm#popup", title: "#{action} #{document.name}", method: "patch",
      msg: doc_check_action_summary(cards, intro_action: action).to_str }
  end

  # X1 — a Documents widget's Folder ID is typed in by an admin, so it is only used when the viewer may see that
  # folder (FolderPolicy#show?) or it is one shared with them as an investor. Any other id is not shown at all
  # (no documents, no folder name) rather than letting the folder tree name another entity's folders.
  def widget_folder_visible?(folder_id, user)
    folder = Folder.find_by(id: folder_id)
    return false if folder.nil?

    Pundit.policy(user, folder).show? || Folder.for_investor(user, folder.entity).exists?(id: folder.id)
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
      document.file.url(response_content_disposition: document.inline_disposition)
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

    # Changed: Instantiate NdaInheritanceResolver for batch lock icon rendering.
    # Why: The tree view uses @nda_resolver to resolve each folder's effective NDA in a single
    # in-memory pass instead of per-folder ancestry walks (N+1). Only created for GP employees
    # who see lock icons; nil for LPs (tree view checks @nda_resolver presence).
    @nda_resolver = (NdaInheritanceResolver.new(folders) if current_user.curr_role_employee?)

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
