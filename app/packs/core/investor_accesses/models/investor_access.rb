class InvestorAccess < ApplicationRecord
  include Trackable.new

  attr_accessor :call_code

  # Make all models searchable
  update_index('investor_access') { self if index_record? }

  validates :email, :first_name, :last_name, presence: true
  validates :first_name, :last_name, length: { maximum: 255 } # matches users.first_name / users.last_name column size
  validates :email, length: { maximum: 255 }
  validates :tag_list, length: { maximum: 120 }, allow_blank: true
  belongs_to :entity
  belongs_to :investor_entity, class_name: "Entity"
  belongs_to :investor # , strict_loading: true

  belongs_to :user, touch: true
  belongs_to :granter, class_name: "User", foreign_key: :granted_by, optional: true
  has_many :noticed_events, as: :record, dependent: :destroy, class_name: "Noticed::Event"

  delegate :name, to: :entity, prefix: :entity
  delegate :investor_name, to: :investor

  validates_uniqueness_of :email, scope: :investor_id, message: "Aready added as a stakeholder"
  validates_format_of :email, with: URI::MailTo::EMAIL_REGEXP, multiline: true
  validates :phone, length: { maximum: 15 }, allow_blank: true

  counter_culture :investor, column_name: proc { |model| model.approved ? 'investor_access_count' : 'unapproved_investor_access_count' },
                             column_names: {
                               ["investor_accesses.approved = ?", true] => 'investor_access_count',
                               ["investor_accesses.approved = ?", false] => 'unapproved_investor_access_count'
                             }

  counter_culture :investor, column_name: proc { |model| model.approved && model.email_enabled ? 'will_receive_email' : nil },
                             column_names: {
                               ["investor_accesses.approved=? AND investor_accesses.email_enabled=?", true, true] => 'will_receive_email'
                             }

  scope :with_tag, ->(tag) { where("investor_accesses.tag_list LIKE ?", "%#{tag}%") }

  scope :approved_for_user, lambda { |user, across_all_entities: false|
    if across_all_entities && user.has_cached_role?(:investor_advisor)
      where("investor_accesses.user_id=? and investor_accesses.approved=?", user.id, true).distinct
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

  scope :email_enabled, lambda {
    where("investor_accesses.email_enabled=?", true)
  }

  scope :email_disabled, lambda {
    where("investor_accesses.email_enabled=?", false)
  }

  scope :approved_for, lambda { |user, entity|
                         where("investor_accesses.user_id=? and investor_accesses.entity_id=? and investor_accesses.approved=?", user.id, entity.id, true)
                       }

  EMAIL_REGEX = URI::MailTo::EMAIL_REGEXP
  validate :cc_must_contain_valid_emails
  def cc_must_contain_valid_emails
    return if cc.blank?

    # Split the emails by comma, remove any leading or trailing spaces and reject any blanks
    emails = cc.split(',').map(&:strip).compact_blank
    email_regex = URI::MailTo::EMAIL_REGEXP
    invalid_emails = emails.grep_v(email_regex)

    errors.add(:cc, "contains invalid emails: #{invalid_emails.join(', ')}") if invalid_emails.any?
    # Remove duplicates and join them back
    self.cc = emails.uniq.join(",")
  end

  before_validation :update_user
  validate :ensure_entity_id

  # This is to check that a user belonging to entity 1 is not given investor_access in an investor belonging to entity 2
  # This rule however does not hold for investor_advisors. This is because they can switch entity_ids to become
  # the advisor for any entity they have access to
  def ensure_entity_id
    errors.add(:user, "cannot be given access. Belongs to #{user.entity.name} id #{user.entity.id} but is being added to #{investor.investor_entity.name} id #{investor.investor_entity.id}") if user && !user.has_cached_role?(:investor_advisor) && user.entity_id != investor.investor_entity_id
  end

  def full_name
    "#{first_name} #{last_name}"
  end

  def to_s
    email
  end

  def update_user
    self.investor_entity_id = investor.investor_entity_id
    self.email = email.strip
    u = User.find_by(email:)
    if u.blank?
      # Setup a new user for this investor_entity_id
      u = User.new(first_name:, last_name:, email:, active: true,
                   phone:, whatsapp_enabled: true, system_created: true,
                   entity_id: investor.investor_entity_id, password: SecureRandom.hex(8))
      u.call_code = call_code if call_code.present?

      # Save the user
      u.save

      # If this user was created in the process of investor access and is the only user, make him company admin
      # u.add_role :company_admin if u.entity.employees.count == 1
    end
    self.user = u
    self.is_investor_advisor = user.has_cached_role?(:investor_advisor)
  end

  def send_notification
    msg = "You have been granted access to '#{entity.name}'"
    InvestorAccessNotifier.with(record: self, entity_id:, email_method: :notify_access, msg:).deliver_later(user) if URI::MailTo::EMAIL_REGEXP.match?(email)
  end

  def send_notification_if_changed
    send_notification if id.present? && saved_change_to_approved?
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[approved created_at email first_name granted_by last_name phone whatsapp_enabled email_enabled is_investor_advisor tag_list].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[investor user]
  end

  def parse_cc
    cc&.scan(%r{\b[a-zA-Z0-9.!\#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\b})&.join(",")
  end

  # When an advisor's InvestorAccess is destroyed, revoke their fund-level AccessRight for any
  # fund where they no longer have another active InvestorAccess (i.e. no remaining approved
  # InvestorAccess for investors in that fund via this user).  Previously the cache rebuild
  # handled this; now we clean the AR directly.
  after_commit :remove_advisor_fund_access_rights, on: :destroy, if: :is_investor_advisor?

  def remove_advisor_fund_access_rights
    fund_ids = investor.capital_commitments.pluck(:fund_id).uniq
    return if fund_ids.empty?

    fund_ids.each do |fund_id|
      # Check whether any other approved InvestorAccess still links this user to an investor
      # in this fund.  If none remain, the user's AR on the fund should be revoked.
      still_has_access = InvestorAccess
                         .joins(investor: :capital_commitments)
                         .where(user_id: user_id, approved: true, is_investor_advisor: true)
                         .where(capital_commitments: { fund_id: fund_id })
                         .where.not(id: id)
                         .exists?

      next if still_has_access

      AccessRight.where(
        entity_id: investor.investor_entity_id,
        owner_type: "Fund",
        owner_id: fund_id,
        user_id: user_id
      ).destroy_all
    end
  end
end
