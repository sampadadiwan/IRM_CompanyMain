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
  has_many :noticed_events, as: :record, dependent: :destroy, class_name: "Noticed::Event"

  NESTED_ATTRIBUTES = %i[id name file tags owner_tag user_id entity_id orignal send_email].freeze
  # counter_culture :entity
  # counter_culture :folder
  # counter_culture :doc_shares # Uncomment if doc_shares_count column is added to documents table

  has_rich_text :text

  validates :name, :file, presence: true
  validates :owner_tag, length: { maximum: 40 }
  validates :tag_list, length: { maximum: 120 }

  delegate :full_path, to: :folder, prefix: :folder
  before_validation :setup_folder, :setup_entity

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
  scope :signed, -> { where(owner_tag: "Signed") }
  scope :generated_approved_or_others, lambda { |model|
    model.documents.includes(:folder).where(owner_tag: "Generated", approved: true).or(model.documents.where.not(owner_tag: "Generated")).or(model.documents.where(owner_tag: nil))
  }
  scope :generated, -> { where(owner_tag: "Generated") }
  scope :not_generated, -> { where(from_template_id: nil) }

  # Find the documents for capital_remittances for a given capital_call_id
  ransacker :capital_call_id do
    Arel.sql <<-SQL.squish
      (SELECT capital_remittances.capital_call_id
      FROM capital_remittances
      WHERE capital_remittances.id = documents.owner_id
        AND documents.owner_type = 'CapitalRemittance'
      LIMIT 1)
    SQL
  end

  # Find the documents whose owner is a CapitalCommitment, and that commitment belongs to a given fund_id
  ransacker :commitments_fund_id do
    Arel.sql(<<-SQL.squish)
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
    sent_for_esign && e_signatures.all? { |esign| esign.email.present? } && approved && RESEND_FOR_ESIGN_STATUSES.include?(esign_status&.downcase) && e_signatures.count.positive?
  end

  def setup_folder
    self.folder = owner.document_folder if folder.nil? && owner
    self.owner ||= folder.owner
    # This marks the document as a template. Templates are used in document (mail merge) generation
    # Templates can also have optional e_signatures, which cause the generated documents to be signed
    self.template ||= owner_tag&.include?("Template")
  end

  def setup_entity
    self.entity_id = folder.entity_id
  end

  def send_notification_for_owner
    notification_users.each do |user|
      DocumentNotifier.with(record: self, entity_id:).deliver_later(user)
    end
  end

  # TODO: This is really inefficient
  def notification_users
    users = access_rights.map(&:users).flatten
    users += self.owner.access_rights.map(&:users).flatten if %w[Fund Deal SecondarySale InvestmentOpportunity].include? owner_type

    users.uniq
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

  def video?
    file&.mime_type&.include?('video')
  end

  def image?
    file&.mime_type&.include?('image')
  end

  def pdf?
    file&.mime_type&.include?('pdf')
  end

  def excel?
    file&.mime_type&.include?('spreadsheet')
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
    approved && !template && !sent_for_esign && SKIP_ESIGN_UPDATE_STATUSES.exclude?(esign_status&.downcase) && e_signatures.count.positive?
  end

  def to_be_approved?
    subject_to_approval? && !approved
  end

  def subject_to_approval?
    # It was generated from some template, but is not a signed doc.
    from_template_id.present? && owner_tag&.exclude?("Signed")
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[approved created_at download esign_status impressions_count locked name orignal owner_tag owner_type tag_list capital_call_id commitments_fund_id].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[approved_by folder]
  end
end
