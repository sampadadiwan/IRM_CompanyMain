class InvestorAccess < ApplicationRecord
  include Trackable
  include ActivityTrackable

  # Make all models searchable
  update_index('investor_access') { self }

  validates :email, :first_name, :last_name, presence: true
  belongs_to :entity
  counter_culture :entity, column_name: proc { |ia| ia.approved ? nil : 'pending_accesses_count' }

  belongs_to :investor # , strict_loading: true
  counter_culture :investor, column_name: proc { |model| model.approved ? 'investor_access_count' : 'unapproved_investor_access_count' }

  belongs_to :user, optional: true, strict_loading: true
  belongs_to :granter, class_name: "User", foreign_key: :granted_by, optional: true

  delegate :name, to: :entity, prefix: :entity
  delegate :investor_name, to: :investor

  scope :approved_for_user, lambda { |user|
    if user.entity && user.entity.is_holdings_entity
      # Employees / Founders done need individual approvals.
      # But the holding company still needs to be added as an investor and give access rights
      where("1=1")
    else
      where("investor_accesses.user_id=? and investor_accesses.approved=?", user.id, true)
    end
  }

  scope :approved, lambda {
    where("investor_accesses.approved=?", true)
  }

  scope :unapproved, lambda {
    where("investor_accesses.approved=?", false)
  }

  scope :approved_for, lambda { |user, entity|
                         where("investor_accesses.user_id=? and investor_accesses.entity_id=? and investor_accesses.approved=?", user.id, entity.id, true)
                       }

  def to_s
    email
  end

  before_save :update_user
  before_save :send_notification_if_changed, if: :approved
  after_create :send_notification, if: :approved

  def update_user
    self.email = email.strip
    u = User.find_by(email:)
    if u.blank?
      u = User.new(first_name:, last_name:, email:, active: true, system_created: true,
                   entity_id: investor.investor_entity_id, password: SecureRandom.hex(8))
      unless send_confirmation
        Rails.logger.debug { "############# Skipping Confirmation for #{u.email}" }
        u.skip_confirmation!
      end
      u.save
    end
    self.user = u
  end

  def send_notification
    InvestorAccessMailer.with(investor_access_id: id).notify_access.deliver_later if URI::MailTo::EMAIL_REGEXP.match?(email)
  end

  def send_notification_if_changed
    send_notification if id.present? && approved_changed?
  end

  def notify_kyc_required
    InvestorKycMailer.with(investor_access_id: id).notify_kyc_required.deliver_later if URI::MailTo::EMAIL_REGEXP.match?(email)
  end
end
