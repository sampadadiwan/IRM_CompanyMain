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

  belongs_to :user, optional: true, strict_loading: true, touch: true
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

  before_validation :update_user
  validate :ensure_entity_id

  def ensure_entity_id
    errors.add(:user, "cannot be given access. Belongs to #{user.entity.name} but is being added to #{investor.investor_entity.name}") if user && user.entity_id != investor.investor_entity_id
  end

  def full_name
    "#{first_name} #{last_name}"
  end

  def to_s
    email
  end

  # after_commit :send_notification_if_changed, if: :approved

  def update_user
    self.email = email.strip
    u = User.find_by(email:)
    if u.blank?
      # Setup a new user for this investor_entity_id
      u = User.new(first_name:, last_name:, email:, active: true, system_created: true,
                   entity_id: investor.investor_entity_id, password: SecureRandom.hex(8))

      # Upload of IAs has a col to prevent confirmations, lets honour that
      unless send_confirmation
        Rails.logger.debug { "############# Skipping Confirmation for #{u.email}" }
        u.skip_confirmation!
      end

      # Save the user
      u.save

      # If this user was created in the process of investor access and is the only user, make him company admin
      u.add_role :company_admin if u.entity.employees.count == 1

    end
    self.user = u
  end

  def send_notification
    InvestorAccessMailer.with(investor_access_id: id).notify_access.deliver_later if URI::MailTo::EMAIL_REGEXP.match?(email)
  end

  def send_notification_if_changed
    send_notification if id.present? && saved_change_to_approved?
  end

  def notify_kyc_required
    InvestorKycMailer.with(investor_access_id: id).notify_kyc_required.deliver_later if URI::MailTo::EMAIL_REGEXP.match?(email)
  end
end
