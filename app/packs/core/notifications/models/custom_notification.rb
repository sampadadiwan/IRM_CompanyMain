class CustomNotification < ApplicationRecord
  include Trackable.new
  include WithFolder
  belongs_to :entity
  belongs_to :owner, polymorphic: true, touch: true

  scope :enabled, -> { where(enabled: true) }
  scope :not_enabled, -> { where(enabled: false) }
  scope :latest, -> { where(latest: true) }
  scope :not_latest, -> { where(latest: false) }
  scope :adhoc_notifications, -> { where(email_method: "adhoc_notification") }

  validates :subject, :body, presence: true
  validates :whatsapp, :subject, length: { maximum: 255 }
  validates :for_type, :email_method, length: { maximum: 100 }

  # validates :email_method, uniqueness: { scope: %i[owner_id owner_type], message: ->(object, _data) { "#{object.email_method} already exists for #{object.owner}" } }
  after_create_commit :reset_latest
  # rubocop:disable Rails/SkipsModelValidations
  def reset_latest
    # Update latest flag for all records with the same email_method, entity_id, owner_id, owner_type except the current record itself to false
    self.class.where(
      email_method: email_method,
      entity_id: entity_id,
      owner_id: owner_id,
      owner_type: owner_type
    ).where.not(id: id).update_all(latest: false)
  end
  # rubocop:enable Rails/SkipsModelValidations

  # We need to ensure that the whatsapp message does not have special characters, otherwise they are escaped by WA and look bad in the actual message
  validate :check_whatsapp
  SPECIAL = "&^#`~".freeze
  WA_REGEXP = /[#{SPECIAL.gsub(/./) { |char| "\\#{char}" }}]/
  def check_whatsapp
    # Check if the whatsapp message has special chars
    errors.add(:whatsapp, "can't have special characters") if WA_REGEXP.match?(whatsapp)
  end

  def to_s
    subject
  end

  def show_link
    show_details_link
  end

  def email_methods
    mailer_methods = if for_type == "InvestorKyc"
                       "InvestorKycMailer".constantize.instance_methods(false).map(&:to_s)
                     elsif for_type == "Send Document"
                       %w[send_document]
                     elsif owner_type == "CapitalCall"
                       "CapitalRemittanceMailer".constantize.instance_methods(false).map(&:to_s) +
                         "CapitalRemittancePaymentMailer".constantize.instance_methods(false).map(&:to_s)
                     elsif owner
                       "#{owner.class.name}Mailer".constantize.instance_methods(false).map(&:to_s)
                     else
                       []
                     end

    mailer_methods.filter { |method| !method.start_with?("set_") }
  end

  def render_erb_string
    renderer = ERB.new(body)
    # You need to set up the binding context. Here it’s done with the top-level binding, but it might be your controller or view context.
    renderer.result(binding)
  end

  def folder_path
    "#{owner.folder_path}/Notifications/#{id_or_random_int}"
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[created_at email_method enabled latest is_erb owner_id owner_type subject whatsapp].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end
end
