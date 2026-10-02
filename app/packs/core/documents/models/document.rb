class Document < ApplicationRecord
  include WithCustomField
  include InvestorsGrantedAccess
  include WithESignatures
  include DocumentScope
  include EntityTouch

  include Trackable.new(associated_with: :owner)

  SIGNATURE_TYPES = { image: "Signature Image", adhaar: "Adhaar eSign", dsc: "Digital Signing" }.freeze
  SKIP_ESIGN_UPDATE_STATUSES = %w[cancelled completed expired voided].freeze
  RESEND_FOR_ESIGN_STATUSES = %w[cancelled voided expired failed].freeze

  MODELS_WITH_DOCS = %w[Fund CapitalCommitment CapitalCall CapitalRemittance CapitalRemittancePayment CapitalDitribution CapitalDitributionPayment Deal DealInvestor InvestmentOpportunity ExpressionOfInterest].freeze

  # Make all models searchable
  update_index('document') { self if index_record? }

  has_many :access_rights, as: :owner, dependent: :destroy
  has_many :permissions, as: :owner, dependent: :destroy
  has_many :tasks, as: :owner, dependent: :destroy
  has_many :e_signatures, dependent: :destroy
  # Allocation run templates that use this document as their statement document. Nullified on
  # delete: the template then fails its pre-run check instead of silently producing nothing.
  has_many :allocation_run_templates, foreign_key: :statement_document_id, dependent: :nullify,
                                      inverse_of: :statement_document
  has_one :esign_log, dependent: :destroy
  has_many :viewed_bies, as: :owner, dependent: :destroy
  has_many :doc_shares, dependent: :destroy
  belongs_to :user

  belongs_to :entity
  belongs_to :folder
  belongs_to :signed_by, class_name: "User", optional: true
  belongs_to :approved_by, class_name: "User", optional: true
  belongs_to :from_template, class_name: "Document", optional: true
  has_many :generated_documents, class_name: "Document", foreign_key: "from_template_id"

  belongs_to :owner, polymorphic: true, optional: true, touch: true

  belongs_to :capital_commitment,
             -> { where(documents: { owner_type: "CapitalCommitment" }) },
             class_name: "CapitalCommitment",
             foreign_key: :owner_id,
             optional: true,
             inverse_of: :documents

  belongs_to :investor_kyc,
             -> { where(documents: { owner_type: "InvestorKyc" }) },
             class_name: "InvestorKyc",
             foreign_key: :owner_id,
             optional: true,
             inverse_of: :documents

  belongs_to :offer,
             -> { where(documents: { owner_type: "Offer" }) },
             class_name: "Offer",
             foreign_key: :owner_id,
             optional: true,
             inverse_of: :documents

  has_many :noticed_events, as: :record, dependent: :destroy, class_name: "Noticed::Event"

  NESTED_ATTRIBUTES = %i[id name file tags owner_tag user_id entity_id orignal send_email].freeze

  # Which engine converts documents generated from this template to PDF. Read from the
  # source template at generation time (see DocumentGeneratorBase#convert_to_accessible_pdf) --
  # "libreoffice" is the existing soffice path and covers every template unless explicitly
  # opted into "m365". See docs/modules/documents/m365_graph_pdf_conversion.md.
  PDF_CONVERSION_ENGINES = %w[libreoffice m365 google_docs].freeze
  # counter_culture :entity
  # counter_culture :folder
  # counter_culture :doc_shares # Uncomment if doc_shares_count column is added to documents table

  has_rich_text :text

  validates :name, presence: true
  validates :file, presence: true, on: :create
  # squish, not strip: a template whose own name carries a trailing space (e.g. "SOA ") makes
  # every document generated from it inherit a DOUBLED space, because DocumentGeneratorBase#upload
  # interpolates "#{doc_template.name} #{start_date} to ...". strip only cleaned the ends, so that
  # internal run survived — and HTML collapses it, making the name look correct everywhere in the
  # UI while exact/LIKE matching (CustomNotification#attachment_names) silently missed it.
  # Applies on assignment and save, so existing rows are untouched until they're next saved.
  normalizes :name, with: ->(name) { name.squish }
  # Doc-gen jobs look a template up by (entity, owner, owner_tag, name) — see
  # CommitmentDocuments#templates — and then key their "delete the previously generated
  # document" step on template.name. A second live template with the same four values is
  # therefore never a "new version": the job renders from both, and the second render deletes
  # the first (investors saw a call notice link go "access denied" seconds after it appeared).
  # Reject it at upload; the user should edit/replace the file on the existing template or
  # delete the old one first. Only tagged templates are checked — an untagged template
  # (owner_tag nil, e.g. TemplateFixAgent's "(AI Fix - draft)" copies) is never picked up by
  # the jobs' owner_tag-filtered scans, so duplicates there are harmless. `conditions` limits
  # the check to live rows: Trackable soft-deletes via paranoia, and a deleted template must
  # not block re-uploading its name. Checked only when the identifying attributes are being
  # set (create, rename, re-tag, re-own): duplicates that pre-date this validation exist in
  # production, and CommitmentDocuments#templates already tolerates them by collapsing to the
  # newest — they must stay editable (file replace, approval, e-sign settings) rather than
  # failing every save until someone notices and deletes one.
  validates :name, uniqueness: { scope: %i[entity_id owner_type owner_id owner_tag],
                                 conditions: -> { where(deleted_at: nil) },
                                 message: "already exists as a template with this tag here. Edit that template " \
                                          "(replace its file) or delete it before uploading another with the same name" },
                   if: :template_identity_changing?
  validates :owner_tag, length: { maximum: 40 }
  validates :tag_list, length: { maximum: 120 }
  # The DB default only applies when the column is left unset; an explicit nil (e.g. from an
  # attributes hash written before this column existed) would otherwise fail the inclusion
  # validation below instead of quietly falling back to the safe default.
  normalizes :pdf_conversion_engine, with: ->(value) { value.presence || "libreoffice" }
  validates :pdf_conversion_engine, inclusion: { in: PDF_CONVERSION_ENGINES }

  delegate :full_path, to: :folder, prefix: :folder
  before_validation :setup_folder, :setup_entity
  before_validation :validate_file_presence_on_update, on: :update

  def validate_file_presence_on_update
    errors.add(:file, "can't be blank") if file.blank? && file_data.blank?
  end

  after_destroy :update_owner
  after_initialize :init

  include FileUploader::Attachment(:file)

  after_create_commit :after_create_commit_callbacks

  scope :generated, -> { where.not(from_template_id: nil) }
  scope :template, -> { where(template: true) }
  scope :approved, -> { where(approved: true) }
  scope :not_approved, -> { where(approved: false) }
  scope :not_template, -> { where(template: false) }
  scope :sent_for_esign, -> { where(sent_for_esign: true) }
  scope :not_sent_for_esign, -> { where(sent_for_esign: false) }
  scope :esign_status_completed, -> { where(esign_status: "completed") }
  scope :esign_status_failed, -> { where(esign_status: "failed") }
  scope :esign_status_requested, -> { where(esign_status: "requested") }
  scope :esign_status_all, -> { where.not(esign_status: nil) }

  scope :signed, -> { where(owner_tag: "Signed") }
  scope :generated_approved_or_others, lambda { |model|
    model.documents.includes(:folder).where(owner_tag: "Generated", approved: true).or(model.documents.where.not(owner_tag: "Generated")).or(model.documents.where(owner_tag: nil))
  }
  scope :generated, -> { where(owner_tag: "Generated") }
  scope :not_generated, -> { where(from_template_id: nil) }

  # A generated (owner_tag == "Generated") document must be approved before it's usable
  # elsewhere (e.g. attached to an email) - anything not generated is unrestricted.
  # Written as an explicit OR (not `.generated.approved` + `.not_generated`) so it can be
  # applied as a single filter on top of an already-scoped/ordered relation.
  scope :exclude_generated_unapproved, -> { where("owner_tag != ? OR owner_tag IS NULL OR approved = ?", "Generated", true) }

  # Find the documents for capital_remittances for a given capital_call_id
  ransacker :capital_call_id do
    Arel.sql <<~SQL.squish
      (SELECT capital_remittances.capital_call_id
      FROM capital_remittances
      WHERE capital_remittances.id = documents.owner_id
        AND documents.owner_type = 'CapitalRemittance'
      LIMIT 1)
    SQL
  end

  # Find the documents for capital_distribution_payments (distribution notices) for a given
  # capital_distribution_id — the distribution page's "View Generated Notices To Approve" filter.
  # Worked examples H3, E22 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
  ransacker :capital_distribution_id do
    Arel.sql <<~SQL.squish
      (SELECT capital_distribution_payments.capital_distribution_id
      FROM capital_distribution_payments
      WHERE capital_distribution_payments.id = documents.owner_id
        AND documents.owner_type = 'CapitalDistributionPayment'
      LIMIT 1)
    SQL
  end

  # Find the documents whose owner is a CapitalCommitment, and that commitment belongs to a given fund_id
  ransacker :commitments_fund_id do
    Arel.sql(<<~SQL.squish)
      (
        SELECT capital_commitments.fund_id
        FROM capital_commitments
        WHERE capital_commitments.id = documents.owner_id
          AND documents.owner_type = 'CapitalCommitment'
        LIMIT 1
      )
    SQL
  end

  def to_s
    name
  end

  # Sequence of callbacks is important here
  def after_create_commit_callbacks
    DocumentPostCreateJob.perform_later(id)
    trigger_side_letter_extraction
  end

  # SideLetterObligationAgent auto-extraction: when a side letter PDF lands on a
  # commitment and the agent has auto_extract_on_upload = Yes, enqueue an
  # extraction run for just that commitment. Guards are ordered cheapest-first —
  # this fires on every document create, so non-commitment uploads must exit on
  # the first string compare.
  def trigger_side_letter_extraction
    return unless owner_type == "CapitalCommitment" && !template

    agent = SupportAgent.enabled.where(entity_id: entity_id, agent_type: "SideLetterObligationAgent").last
    return if agent.nil?
    # Feature is dark for the tenant — don't extract obligations nobody can see.
    return unless agent.entity_flag_enabled?
    return unless (agent.json_fields || {})["auto_extract_on_upload"].to_s.casecmp("yes").zero?
    # Matches the configured name label, or a "Side Letter"/"SideLetter" tag in any casing.
    return unless SideLetterObligationAgent.side_letter_document?(self, SideLetterObligationAgent.doc_label(agent))

    SupportAgentJob.perform_later(support_agent_id: agent.id, target_type: "CapitalCommitment", target_id: owner_id)
  end

  def post_create_actions
    setup_access_rights
    update_owner
    send_notification_for_owner if send_email
  end

  before_save :init
  def init
    self.send_email = false if send_email.nil?
    self.approved = false if approved.nil?
    self.template = false if template.nil?
    self.sent_for_esign = false if sent_for_esign.nil?
  end

  def setup_folder_defaults
    if folder
      self.printing = folder.printing
      self.download = folder.download
      self.orignal = folder.orignal
    end
  end

  def esign_completed?
    esign_status&.casecmp?("completed")
  end

  def esign_expired?
    esign_status&.casecmp?("expired") || esign_status&.casecmp?("cancelled")
  end

  def esign_failed?
    esign_status&.casecmp?("failed")
  end

  def esign_voided?
    esign_status&.casecmp?("voided")
  end

  def eligible_for_esign_update?
    SKIP_ESIGN_UPDATE_STATUSES.exclude?(esign_status&.downcase)
  end

  def resend_for_esign?
    sent_for_esign && e_signatures.all? { |esign| esign.email.present? } && approved && RESEND_FOR_ESIGN_STATUSES.include?(esign_status&.downcase) && e_signatures.any?
  end

  def setup_folder
    self.folder = owner.document_folder if folder.nil? && owner
    self.owner ||= folder.owner
    # This marks the document as a template. Templates are used in document (mail merge) generation
    # Templates can also have optional e_signatures, which cause the generated documents to be signed
    # Coerce to a strict boolean: owner_tag&.include? returns nil when owner_tag is nil, and
    # assigning nil here violates the NOT NULL constraint on documents.template if this record
    # is later persisted by a callbacks-skipping save (e.g. Shrine's post-promotion persist)
    self.template ||= owner_tag&.include?("Template") || false
  end

  def setup_entity
    self.entity_id = folder.entity_id
  end

  # Guard for the template-name uniqueness validation above: a tagged template whose
  # identifying attributes (name, tag, owner, entity) are new or changing on this save.
  def template_identity_changing?
    return false unless template? && owner_tag.present?

    new_record? || name_changed? || owner_tag_changed? || owner_id_changed? || owner_type_changed? || entity_id_changed?
  end

  def send_notification_for_owner
    recipients = notification_recipients
    log_commitments_without_access(recipients.map { |_user, investor| investor&.id })

    recipients.each do |user, investor|
      # investor_id is what unlocks the cc addresses on the receiving side - see
      # DocumentNotifier#email_data. Without it a data room document emails the contact with
      # only the entity-wide cc, silently dropping their advisor.
      DocumentNotifier.with(record: self, entity_id:, investor_id: investor&.id).deliver_later(user)
    end
  end

  # The access right - not the person - is the unit of delivery.
  #
  # One contact can reach the same document through several access rights: a fund's data room
  # is shared with three stakeholders, and the same person is a named contact for all three.
  # Each of those stakeholders carries its own cc addresses (InvestorAccess#cc, and the cc on
  # their commitments in this fund), so collapsing them into one recipient would force us to
  # pick one stakeholder's cc list and drop the rest. Instead the contact gets one email per
  # stakeholder, each cc'd correctly - the same way they already receive one email per
  # commitment for commitment-filed documents.
  #
  # Returns [user, investor] pairs deduped on [user_id, investor_id], so several rights
  # pointing at the SAME stakeholder still produce a single email. `investor` is nil for a
  # right granted directly to a named user (usually an employee).
  #
  # See docs/modules/notifications/document_notification_cc_resolution.md.
  # TODO: This is really inefficient
  def notification_recipients
    rights = access_rights.to_a
    rights += owner.access_rights.to_a if %w[Fund Deal SecondarySale InvestmentOpportunity].include? owner_type

    rights.flat_map(&:notification_recipients)
          .uniq { |user, investor| [user&.id, investor&.id] }
          .select(&:first)
  end

  # Cap on the stakeholder names in the log line below, so a fund with hundreds of uncovered
  # stakeholders cannot emit a giant entry. Mirrors ImportCapitalCommitment::MAX_NAMES_IN_ALERT.
  MAX_UNCOVERED_NAMES_LOGGED = 10

  # Visibility for the commitment-vs-access-right gap.
  #
  # A commitment grants fund access when it is created (CapitalCommitment#grant_access_to_fund,
  # called from CapitalCommitmentCreate and ImportCapitalCommitment), which cascades onto the
  # Data Room folder via Fund#access_rights_changed and then onto every document uploaded there.
  # So an LP holding a commitment in this fund normally has an access right that delivers this
  # document.
  #
  # When they don't - the right was revoked, or the commitment predates the grant - they are
  # left out of the notification with nothing to show it happened. Log it so the gap is visible.
  #
  # Called from the senders (send_notification_for_owner, DocumentSender), not from
  # notification_recipients: the "who gets emailed" preview resolves the same recipients without
  # sending anything, and a warning saying people "were not notified" would be untrue there.
  #
  # Deliberately only logs: it does NOT add them as recipients. The access right is also what
  # makes the link in the email work, so notifying without one would send mail that 403s on
  # click. The fix for a real gap is to restore the access right. Reviewed alternatives are in
  # docs/modules/notifications/document_notification_cc_resolution.md.
  def log_commitments_without_access(notified_investor_ids)
    return unless owner_type == "Fund"

    # where.not(investor_id: []) is a no-op filter in Rails, so an empty notified list
    # correctly reports every committed stakeholder as uncovered.
    uncovered = CapitalCommitment.where(fund_id: owner_id)
                                 .where.not(investor_id: notified_investor_ids.compact)
                                 .distinct
                                 .pluck(:investor_id)
    return if uncovered.empty?

    names = Investor.where(id: uncovered).distinct.limit(MAX_UNCOVERED_NAMES_LOGGED).pluck(:investor_name)
    more = uncovered.size - names.size
    Rails.logger.warn(
      "Document #{id} (#{name}) in Fund #{owner_id} data room: #{uncovered.size} stakeholder(s) " \
      "hold a commitment in this fund but no access right delivers this document, so they were " \
      "not notified - #{names.join(', ')}#{" and #{more} more" if more.positive?}"
    )
  end

  # The distinct people notification_recipients would email - for callers that only need
  # "will anyone receive this?" or a list of names. Per-stakeholder cc resolution needs the
  # pairs, so senders use notification_recipients instead.
  def notification_users
    notification_recipients.map(&:first).uniq
  end

  def setup_access_rights
    folder.access_rights.each do |folder_ar|
      doc_ar = folder_ar.dup
      doc_ar.owner = self
      doc_ar.access_type = 'Document'
      doc_ar.save
    end
  end

  def self.documents_for(current_user, entity)
    # Is this user from an investor
    investor = Investor.for(current_user, entity).first

    if investor.present?

      entity.documents.joins(:access_rights)
            .where("access_rights.access_to=? or access_rights.access_to_investor_id=?",
                   current_user.email, investor.id)

    else
      entity.documents.joins(:access_rights)
            .where("access_rights.access_to=?", current_user.email)

    end
  end

  def m365_pdf_conversion?
    pdf_conversion_engine == "m365"
  end

  def google_docs_pdf_conversion?
    pdf_conversion_engine == "google_docs"
  end

  def video?
    file&.mime_type&.include?('video')
  end

  def image?
    file&.mime_type&.include?('image')
  end

  def pdf?
    file&.mime_type&.include?('pdf')
  end

  def csv?
    file&.mime_type&.include?('csv')
  end

  def excel?
    file&.mime_type&.include?('spreadsheet')
  end

  def ppt?
    mime_type_includes?('presentation') || mime_type_includes?('powerpoint') || mime_type_includes?('ms-powerpoint')
  end

  def mime_type_includes?(file_type)
    file&.mime_type&.include?(file_type)
  end

  def uploaded_file_name
    file.metadata['filename'] if file.metadata
  end

  def uploaded_file_extension
    file.metadata['filename'].split(".")[-1] if file.metadata
  end

  def extension
    extension = File.extname(file.original_filename) # => ".jpg", ".png", etc.
    extension[1..] # => "jpg", "png", etc.
  end

  def name_with_extension
    "#{name.gsub(%r{[/\\,:*?"<>|#]}, ' ').strip}.#{extension}"
  end

  def duplicate(required_attributes = nil)
    doc = required_attributes ? Document.new(attributes.slice(*required_attributes)) : dup
    doc.file_data = nil
    doc.name = nil
    doc.id = nil
    doc
  end

  def update_owner
    owner.document_changed(self) if owner.respond_to? :document_changed
  end

  def to_be_esigned?
    approved && !template && !sent_for_esign && SKIP_ESIGN_UPDATE_STATUSES.exclude?(esign_status&.downcase) && e_signatures.any?
  end

  # Distinct capital call ids for the call notices (generated, remittance-owned) in `documents`.
  # Plucked in SQL (a handful of ids) so the documents table is never loaded; plucked rather than
  # kept as a subquery because callers approve the documents, which takes them out of the scope.
  def self.call_ids_for_notices(documents)
    CapitalRemittance.where(id: documents.where(owner_type: "CapitalRemittance", owner_tag: "Generated").select(:owner_id))
                     .distinct.pluck(:capital_call_id)
  end

  # Distinct capital distribution ids for the distribution notices (generated, payment-owned) in
  # `documents` — the distribution counterpart of call_ids_for_notices, plucked the same way.
  # Worked examples E18 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
  def self.distribution_ids_for_notices(documents)
    CapitalDistributionPayment.where(id: documents.where(owner_type: "CapitalDistributionPayment", owner_tag: "Generated").select(:owner_id))
                              .distinct.pluck(:capital_distribution_id)
  end

  # { journey record class => ids } for the notices in `documents` — read BEFORE approving them,
  # then handed to notices_journey_progress! once the approval is done.
  def self.notice_journey_ids(documents)
    { CapitalCall => call_ids_for_notices(documents), CapitalDistribution => distribution_ids_for_notices(documents) }
  end

  # Re-checks, once each, the journeys of the calls and distributions whose notices were approved
  # (bulk approve, approve by date range). No-op for records without a journey.
  # Worked examples J2.2 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
  # Worked examples E18 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
  def self.notices_journey_progress!(journey_ids, actor:)
    journey_ids.each { |klass, ids| klass.journey_progress_for(ids, actor:) if ids.any? }
  end

  # The call or distribution whose journey this generated notice counts towards, or nil
  def notice_journey_record
    return unless owner_tag == "Generated"

    case owner_type
    when "CapitalRemittance" then owner&.capital_call
    when "CapitalDistributionPayment" then owner&.capital_distribution
    end
  end

  def to_be_approved?
    subject_to_approval? && !approved
  end

  def signed?
    owner_tag == "Signed"
  end

  def subject_to_approval?
    # It was generated from some template, but is not a signed doc.
    # Use != instead of safe-navigation exclude? to avoid nil returning falsy when owner_tag is nil.
    from_template_id.present? && owner_tag != "Signed"
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[approved created_at download esign_status impressions_count locked name orignal owner_tag owner_type tag_list capital_call_id capital_distribution_id commitments_fund_id as_of template].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[approved_by folder e_signatures capital_commitment investor_kyc]
  end

  def is_soa_template?
    !!((tag_list&.downcase =~ /\b#{Regexp.escape('soa')}\b/) ||
    (owner_tag&.downcase =~ /\b#{Regexp.escape('soa')}\b/) ||
    (tag_list&.downcase =~ /\b#{Regexp.escape('investor statement')}\b/) ||
    (owner_tag&.downcase =~ /\b#{Regexp.escape('investor statement')}\b/))
  end
end
