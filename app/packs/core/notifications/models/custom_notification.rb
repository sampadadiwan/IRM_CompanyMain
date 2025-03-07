class CustomNotification < ApplicationRecord
  include Trackable.new
  include WithFolder
  belongs_to :entity
  belongs_to :owner, polymorphic: true, touch: true

  scope :enabled, -> { where(enabled: true) }
  scope :adhoc_notifications, -> { where(email_method: "adhoc_notification") }

  validates :subject, :body, presence: true
  validates :whatsapp, :subject, length: { maximum: 255 }
  validates :for_type, :email_method, length: { maximum: 100 }

  # validates :email_method, uniqueness: { scope: %i[owner_id owner_type], message: ->(object, _data) { "#{object.email_method} already exists for #{object.owner}" } }

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
    !no_link
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
end
