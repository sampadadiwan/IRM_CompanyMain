# == Schema Information
#
# Table name: documents
#
#  id                :integer          not null, primary key
#  name              :string(255)
#  visible_to        :string(255)      default("--- []\n")
#  text              :string(255)      default("--- []\n")
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  file_file_name    :string(255)
#  file_content_type :string(255)
#  file_file_size    :integer
#  file_updated_at   :datetime
#  entity_id         :integer          not null
#  deleted_at        :datetime
#  folder_id         :integer          not null
#  impressions_count :integer          default("0")
#

class Document < ApplicationRecord
  include Trackable
  include Impressionable

  # Make all models searchable
  update_index('document') { self }

  acts_as_taggable_on :tags

  has_many :access_rights, as: :owner, dependent: :destroy
  has_many :permissions, as: :owner, dependent: :destroy

  belongs_to :entity
  belongs_to :folder
  belongs_to :owner, polymorphic: true, optional: true

  counter_culture :entity
  counter_culture :folder

  has_rich_text :text
  has_one_attached :video, service: :amazon

  # Customize form
  belongs_to :form_type, optional: true
  serialize :properties, Hash

  validates :name, presence: true

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
    self.folder = owner.owner_folder if folder.nil? && owner
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
    file.mime_type&.include?('video')
  end

  def image?
    file.mime_type&.include?('image')
  end
end
