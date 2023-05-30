class Document < ApplicationRecord
  include Trackable
  include Impressionable
  include WithCustomField
  include InvestorsGrantedAccess

  SIGNATURE_TYPES = { image: "Signature Image", adhaar: "Adhaar eSign", dsc: "Digital Signing" }.freeze

  serialize :signature_type

  # Make all models searchable
  update_index('document') { self }

  has_many :access_rights, as: :owner, dependent: :destroy
  has_many :permissions, as: :owner, dependent: :destroy
  has_many :tasks, as: :owner, dependent: :destroy
  belongs_to :user
  has_one :adhaar_esign

  belongs_to :entity, touch: true
  belongs_to :folder
  belongs_to :signed_by, class_name: "User", optional: true
  belongs_to :from_template, class_name: "Document", optional: true

  belongs_to :owner, polymorphic: true, optional: true, touch: true

  NESTED_ATTRIBUTES = %i[id name file tags owner_tag user_id].freeze
  counter_culture :entity
  counter_culture :folder

  has_rich_text :text

  validates :name, :file, presence: true

  delegate :full_path, to: :folder, prefix: :folder
  before_validation :setup_folder, :setup_entity

  after_save :send_notification_for_owner
  after_create :setup_access_rights
  after_initialize :init

  include FileUploader::Attachment(:file)

  scope :generated, -> { where(owner_tag: "Generated") }

  def to_s
    name
  end

  def init
    self.send_email = true if send_email.nil?
  end

  def setup_folder_defaults
    if folder
      self.printing = folder.printing
      self.download = folder.download
      self.orignal = folder.orignal
    end
  end

  def setup_folder
    self.folder = owner.document_folder if folder.nil? && owner
    self.owner ||= folder.owner
    self.template = owner_tag&.include?("Template")
  end

  def setup_entity
    self.entity_id = folder.entity_id
  end

  def send_notification_for_owner
    DocumentMailer.with(id:).notify_new_document_to_investors.deliver_later if owner_tag != "Template" && send_email
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

  scope :for_investor, lambda { |user, entity|
    joins(:access_rights)
      .merge(AccessRight.access_filter(user))
      .joins(entity: :investors)
      # Ensure that the user is an investor and tis investor has been given access rights
      .where("entities.id=?", entity.id)
      .where("investors.investor_entity_id=?", user.entity_id)
      # Ensure this user has investor access
      .joins(entity: :investor_accesses)
      .merge(InvestorAccess.approved_for_user(user))
  }

  def video?
    file&.mime_type&.include?('video')
  end

  def image?
    file&.mime_type&.include?('image')
  end

  after_update :update_owner
  after_destroy :update_owner
  def update_owner
    owner.document_changed(self) if owner.respond_to? :document_changed
  end
end
