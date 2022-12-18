class Document < ApplicationRecord
  include Trackable
  include Impressionable

  SIGNATURE_TYPES = { image: "Signature Image", adhaar: "Adhaar eSign", dsc: "Digital Signing" }.freeze

  serialize :signature_type

  # Make all models searchable
  update_index('document') { self }

  acts_as_taggable_on :tags

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

  # Customize form
  belongs_to :form_type, optional: true
  serialize :properties, Hash

  validates :name, :file, presence: true

  delegate :full_path, to: :folder, prefix: :folder
  before_validation :setup_folder, :setup_entity
  after_create :setup_access_rights

  include FileUploader::Attachment(:file)

  def to_s
    name
  end

  def setup_entity
    self.entity_id = folder.entity_id
  end

  def setup_folder
    self.folder = owner.document_folder if folder.nil? && owner
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
      .merge(AccessRight.access_filter)
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

  after_create_commit :send_notification_for_owner
  def send_notification_for_owner
    DocumentMailer.with(id:).notify_new_document.deliver_later if %w[SecondarySale Fund InvestmentOpportunity].include? owner_type
  end

  def investor_users
    User.joins(investor_accesses: :investor).where("investor_accesses.approved=? and investor_accesses.entity_id=?", true, entity_id).merge(Investor.owner_access_rights(owner, nil))
  end
end
