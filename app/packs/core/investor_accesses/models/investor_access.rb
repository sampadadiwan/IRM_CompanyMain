class InvestorAccess < ApplicationRecord
  include Trackable
  include ActivityTrackable

  # Make all models searchable
  update_index('investor_access') { self }

  validates :email, :first_name, :last_name, presence: true
  belongs_to :entity
  belongs_to :investor_entity, class_name: "Entity"
  belongs_to :investor # , strict_loading: true

  belongs_to :user, optional: true, strict_loading: true, touch: true
  belongs_to :granter, class_name: "User", foreign_key: :granted_by, optional: true

  delegate :name, to: :entity, prefix: :entity
  delegate :investor_name, to: :investor

  validates_uniqueness_of :email, scope: :investor_id

  counter_culture :entity, column_name: proc { |ia| ia.approved ? nil : 'pending_accesses_count' }
  counter_culture :investor, column_name: proc { |model| model.approved ? 'investor_access_count' : 'unapproved_investor_access_count' }

  scope :approved_for_user, lambda { |user|
    if user.entity && user.entity.is_holdings_entity
      # Employees / Founders done need individual approvals.
      # But the holding company still needs to be added as an investor and give access rights
      where("1=1")
    else
      where("investor_accesses.investor_entity_id=? and investor_accesses.user_id=? and investor_accesses.approved=?", user.entity_id, user.id, true)
    end
  }

  scope :approved, lambda {
    where("investor_accesses.approved=?", true)
  }

  scope :not_investor_advisors, lambda {
    where("investor_accesses.is_investor_advisor=?", false)
  }

  scope :investor_advisors, lambda {
    where("investor_accesses.is_investor_advisor=?", true)
  }

  scope :unapproved, lambda {
    where("investor_accesses.approved=?", false)
  }

  scope :approved_for, lambda { |user, entity|
                         where("investor_accesses.user_id=? and investor_accesses.entity_id=? and investor_accesses.approved=?", user.id, entity.id, true)
                       }

  before_validation :update_user
  validate :ensure_entity_id

  # This is to check that a user belonging to entity 1 is not given investor_access in an investor belonging to entity 2
  # This rule however does not hold for investor_advisors. This is because they can switch entity_ids to become
  # the advisor for any entity they have access to
  def ensure_entity_id
    errors.add(:user, "cannot be given access. Belongs to #{user.entity.name} but is being added to #{investor.investor_entity.name}") if user && !user.has_cached_role?(:investor_advisor) && user.entity_id != investor.investor_entity_id
  end

  def full_name
    "#{first_name} #{last_name}"
  end

  def to_s
    email
  end

  # after_commit :send_notification_if_changed, if: :approved

  def update_user
    self.investor_entity_id = investor.investor_entity_id
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
      # u.add_role :company_admin if u.entity.employees.count == 1
    end
    self.user = u
    self.is_investor_advisor = user.investor_advisor?
  end

  def send_notification
    InvestorAccessNotification.with(entity_id:, investor_access_id: id, email_method: :notify_access, msg: "Investor Access Granted to #{entity.name}").deliver_later(user) if URI::MailTo::EMAIL_REGEXP.match?(email)
  end

  def send_notification_if_changed
    send_notification if id.present? && saved_change_to_approved?
  end

  def notify_kyc_required
    InvestorAccessNotification.with(entity_id:, investor_access_id: id, email_method: :notify_kyc_required, msg: "Investor KYC required for #{entity.name}").deliver_later(user) if URI::MailTo::EMAIL_REGEXP.match?(email)
  end
end
