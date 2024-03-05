class CustomNotification < ApplicationRecord
  belongs_to :entity
  belongs_to :owner, polymorphic: true

  validates :subject, :body, :whatsapp, presence: true
  validates :whatsapp, :subject, length: { maximum: 255 }
  validates :for_type, :email_method, length: { maximum: 100 }

  def to_s
    subject
  end

  def show_link
    !no_link
  end

  def email_methods
    if for_type == "InvestorKyc"
      "InvestorKycMailer".constantize.instance_methods(false).map(&:to_s)
    elsif for_type == "Commitment Agreement"
      %w[send_commitment_agreement]
    elsif owner_type == "CapitalCall"
      "CapitalRemittanceMailer".constantize.instance_methods(false).map(&:to_s)
    elsif owner
      "#{owner.class.name}Mailer".constantize.instance_methods(false).map(&:to_s)
    else
      []
    end
  end
end
