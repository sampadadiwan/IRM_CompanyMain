# This is a very important model and indicates that an entity is willing to allow the user
# (who is from another advisory company), advisor access to this company. This essentially allows the user to switch
# his entity id to this entity_id and thus gain access to funds, deals, etc which are permissioned

# Workflow
# 1. Entity makes a user an investor advisor in ones own firm
# 2. Entity can grant access to specific funds, deals etc to this investor advisor
# 3. The advisor can login and choose to switch to become an advisor for this entity (This essentially involves switching his entity_id to this entity_id)
# 4. Then he becomes like an employee whose access is controlled via access rights

class InvestorAdvisor < ApplicationRecord
  include UserEnabled
  include Trackable.new

  # Roles an entity admin may grant to an advisor on switch.
  # :super is intentionally excluded — it is a platform-level role that no
  # entity admin has authority to bestow.
  ALLOWED_ADVISOR_ROLES = %w[company_admin employee investor investor_advisor rm].freeze

  belongs_to :entity
  belongs_to :user
  has_many :investors,
           primary_key: :entity_id,
           foreign_key: :investor_entity_id,
           class_name: "Investor"

  belongs_to :import_upload, optional: true
  belongs_to :created_by, class_name: "User", optional: true

  # Set by the controller to the logged-in user so the model can enforce
  # role-grant restrictions without coupling to request context.
  attr_accessor :acting_user

  before_validation :ensure_user
  validates_uniqueness_of :email, scope: :entity_id
  validate :allowed_roles_are_valid
  validate :company_admin_role_requires_company_admin_granter, if: -> { acting_user.present? }

  serialize :allowed_roles, type: Array

  def ensure_user
    self.user = User.find_by(email:)
    errors.add(:email, "No existing user found in the system. Advisor has not been setup.") unless user
    errors.add(:email, "User has not been setup as an investor advisor.") if user && !user.has_cached_role?(:investor_advisor)
  end

  # Finding 2: Validate that allowed_roles contains only permitted roles.
  # This prevents privilege escalation where an advisor could be granted
  # platform-level roles like :super.
  def allowed_roles_are_valid
    invalid = Array(allowed_roles) - ALLOWED_ADVISOR_ROLES
    errors.add(:allowed_roles, "contains invalid role(s): #{invalid.join(', ')}") if invalid.any?
  end

  # Finding 2: Ensure that 'company_admin' can only be granted by an existing
  # company admin. This prevents a regular employee from escalating an advisor's
  # privileges to administrative level.
  def company_admin_role_requires_company_admin_granter
    return unless Array(allowed_roles).include?('company_admin')
    return if acting_user.has_cached_role?(:company_admin)

    errors.add(:allowed_roles, "cannot include 'company_admin' unless granted by a company admin")
  end

  def switch(user)
    user.entity = entity
    user.investor_advisor_id = id
    user.setup_defaults
    user.save

    # Finding 8: Role assignment must be atomic. Wrapping in a transaction
    # ensures that if any role addition fails, the user isn't left in a
    # broken state with zero roles (lockout scenario).
    ActiveRecord::Base.transaction do
      user.roles.delete_all
      allowed_roles.each { |role| user.add_role(role) }
      user.add_role(:investor_advisor)
    end
  end

  def self.revert(user, persona)
    user.entity_id = user.advisor_entity_id
    user.investor_advisor_id = nil
    user.setup_defaults
    user.save

    # Finding 8: Role assignment must be atomic during revert.
    ActiveRecord::Base.transaction do
      user.roles.delete_all
      user.advisor_entity_roles&.split(",")&.each { |role| user.add_role(role.strip) }
      user.add_role(:investor_advisor) if user.roles.reload.empty?
    end

    # In case we also have a persona sent in
    user.set_persona(persona) if persona.present?
  end

  after_destroy :remove_access_rights
  def remove_access_rights
    AccessRight.where(entity_id:, user_id:).find_each(&:destroy)
    InvestorAccess.where(investor_entity_id: entity_id, email:).delete_all
  end

  # Set by import_upload, to indicate where this advisor was added
  attr_accessor :owner_name

  after_create :notify_investor_team
  after_commit :refresh_user_cache, on: :create

  def refresh_user_cache
    # When an advisor record is created, we need to refresh the user's cache
    # for this entity so any pre-existing AccessRights are picked up.
    user.reset_access_rights_cache
  end

  def notify_investor_team
    entity.employees.active.company_admins.each do |employee|
      InvestorAdvisorNotifier.with(record: self, entity_id:, owner_name:, email_method: :notify_investor_advisor_addition, msg: "Investor Advisor #{user.full_name} has been added").deliver_later(employee)
    end
  end
end
