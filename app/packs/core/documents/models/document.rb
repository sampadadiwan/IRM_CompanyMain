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

  def self.for_investor(user, entity)
    Document
      # Ensure the access rghts for Document
      .joins(:access_rights)
      .merge(AccessRight.access_filter)
      .joins(entity: :investors)
      # Ensure that the user is an investor and tis investor has been given access rights
      .where("entities.id=?", entity.id)
      .where("investors.investor_entity_id=?", user.entity_id)
      # Ensure this user has investor access
      .joins(entity: :investor_accesses)
      .merge(InvestorAccess.approved_for_user(user))
  end

  def video?
    file&.mime_type&.include?('video')
  end

  def image?
    file&.mime_type&.include?('image')
  end

  def display_signature_type
    SIGNATURE_TYPES.select { |k, _v| signature_type.include?(k.to_s) }.values.join(",")
  end

  def access_rights_changed(access_right_id)
    DocumentMailer.with(access_right_id:).notify_signature_required.deliver_later if signature_enabled
  end

  # def self.check_signature

  #   # This example requires the Chilkat API to have been previously unlocked.
  #   # See Global Unlock Sample for sample code.

  #   pdf = Chilkat::CkPdf.new

  #   # Load a PDF that has cryptographic signatures to be validated
  #   success = pdf.LoadFile("public/sample_uploads/SignedDoc.pdf")
  #   if success == false
  #     Rails.logger.debug { "#{pdf.lastErrorText}\n" }
  #     exit
  #   end

  #   # Each time we verify a signature, information about the signature is written into
  #   # sigInfo (replacing whatever sigInfo previously contained).
  #   sigInfo = Chilkat::CkJsonObject.new
  #   sigInfo.put_EmitCompact(false)

  #   # Iterate over each signature and validate each.
  #   numSignatures = pdf.get_NumSignatures
  #   validated = false
  #   i = 0
  #   while i < numSignatures
  #     validated = pdf.VerifySignature(i, sigInfo)
  #     Rails.logger.debug { "Signature #{i} validated: #{validated}\n" }
  #     Rails.logger.debug { "#{sigInfo.emit}\n" }
  #     i += 1
  #   end

  #   sigInfo.emit
  # end
end
