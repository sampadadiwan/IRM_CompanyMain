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
  ALLOWED_ADVISOR_ROLES = %w[approver company_admin employee investor investor_advisor rm].freeze

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
  # Only on create: an existing grant must stay editable even if its advisor was set up badly
  # before this check existed, otherwise support cannot fix anything from the UI.
  before_validation :ensure_advisor_home, on: :create
  validate :advisor_home_is_recorded, on: :create
  validates_uniqueness_of :email, scope: :entity_id
  validate :allowed_roles_are_valid
  validate :company_admin_role_requires_company_admin_granter, if: -> { acting_user.present? }

  serialize :allowed_roles, type: Array

  def ensure_user
    self.user = User.find_by(email:)
    errors.add(:email, "No existing user found in the system. Advisor has not been setup.") unless user
    errors.add(:email, "User has not been setup as an investor advisor.") if user && !user.has_cached_role?(:investor_advisor)
  end

  # An advisor's own firm is recorded on the user as advisor_entity_id, and the topbar company
  # switcher appears only when it is set. User#setup_defaults is the only thing that writes it,
  # and it runs from before_create - so a user who already existed before being made an advisor
  # never gets it, and the symptom ("no switcher") does not show up until they next sign in.
  #
  # Filling it in here, when their firm is already the right kind of company, closes that gap at
  # the point the grant is created rather than leaving it for support to find.
  def ensure_advisor_home
    return if user.blank? || user.advisor_entity_id.present?
    return unless user.entity&.entity_type == "Investor Advisor"
    # setup_defaults also flips active back on and fills in blank permissions. Repairing a live
    # advisor is the point; silently reactivating a switched-off account as a side effect of
    # adding a grant is not, so leave those alone and let the validation below explain.
    return unless user.active?

    user.setup_defaults
    user.save
  end

  # Whatever ensure_advisor_home could not fix: the user does not belong to an advisory firm at
  # all, so there is nothing to record as their home. Creating the grant anyway produces an
  # advisor who can be added and looks correct everywhere except that they can never switch.
  def advisor_home_is_recorded
    return if user.blank?
    # Deliberately the stored value, not user.advisor_entity_id: ensure_advisor_home assigns it
    # in memory before saving, so an in-memory read would pass even when that save was refused
    # and the advisor would still end up with no switcher.
    return if User.where(id: user.id).pick(:advisor_entity_id).present?

    errors.add(:email, advisor_home_error_message)
  end

  def advisor_home_error_message
    if user.entity&.entity_type == "Investor Advisor"
      "belongs to #{user.entity.name}, but their advisor settings could not be recorded automatically - the " \
        "account is inactive or could not be saved. Open the user, fix and save them, then add them as an advisor."
    else
      "belongs to #{user.entity&.name || 'no company'}, which is not an advisory firm, so this user " \
        "would have no company switcher after signing in. Create their advisory firm as a company of " \
        "type 'Investor Advisor', move the user into it, then add them as an advisor."
    end
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
      # setup_defaults above has already set entity_type to the home entity's type.
      user.home_role_names(home_entity_type: user.entity_type).each { |role| user.add_role(role) }
    end

    # In case we also have a persona sent in
    user.set_persona(persona) if persona.present?
  end

  # Everything that must be true for THIS grant to appear in the topbar switcher and to work
  # once switched into. Returns an array of issue hashes - see User#investor_advisor_setup_issues
  # for the shape - so the same list can be printed in the console or rendered on the user page.
  def setup_issues
    issues = []

    if deleted_at.present?
      issues << { severity: :blocker,
                  summary: "This advisor grant has been deleted",
                  detail: "The grant for #{entity_label} was deleted on #{deleted_at.to_date}. Deleted grants are " \
                          "hidden everywhere in the app, so it will not appear in the switcher.",
                  fix: "If this was a mistake, restore the grant. Otherwise no action is needed." }
    end

    if entity.nil?
      issues << { severity: :blocker,
                  summary: "This advisor grant points at a company that no longer exists",
                  detail: "The grant refers to entity #{entity_id}, which is not in the system.",
                  fix: "Delete this grant and re-add the advisor to the correct company." }
    elsif !entity.active?
      issues << { severity: :blocker,
                  summary: "#{entity.name} is deactivated, so it is missing from the switcher",
                  detail: "The switcher only lists active companies. The grant itself is fine.",
                  fix: "Reactivate #{entity.name} if the advisor still needs access to it." }
    end

    if user.nil?
      issues << { severity: :blocker,
                  summary: "This advisor grant is not linked to a user account",
                  detail: "The grant refers to user #{user_id}, which is not in the system.",
                  fix: "Delete this grant and re-add the advisor using their email address." }
    elsif !user.has_cached_role?(:investor_advisor)
      issues << { severity: :blocker,
                  summary: "#{user.email} is not marked as an investor advisor",
                  detail: "Without the investor advisor role the app will refuse the switch into #{entity_label}.",
                  fix: "Give the user the investor advisor role, then ask them to sign in again." }
    end

    roles = Array(allowed_roles)
    if roles.empty?
      issues << { severity: :blocker,
                  summary: "No roles are granted for #{entity_label}",
                  detail: "Switching replaces the advisor's roles with the ones listed on this grant. With none " \
                          "listed they arrive at #{entity_label} with no working role and will not see much.",
                  fix: "Edit this advisor and tick the roles they should have at #{entity_label} " \
                       "(usually Employee, or Investor for an LP)." }
    end

    # allowed_roles_are_valid compares against a String list, so a row serialized with symbols
    # (YAML "- :employee") fails validation even though the names themselves are fine - the grant
    # still switches, but it can no longer be saved from the UI.
    invalid = roles - ALLOWED_ADVISOR_ROLES
    if invalid.any?
      issues << if invalid.all?(Symbol) && invalid.map(&:to_s).intersect?(ALLOWED_ADVISOR_ROLES)
                  { severity: :warning,
                    summary: "This grant cannot be saved from the Edit screen",
                    detail: "Its roles (#{invalid.join(', ')}) were stored in an older format. They work, " \
                            "but saving the advisor now fails with a misleading \"invalid role\" message.",
                    fix: "Re-tick the roles and save - or leave it alone if nobody needs to edit this advisor." }
                else
                  { severity: :warning,
                    summary: "This grant lists roles that are not allowed: #{invalid.join(', ')}",
                    detail: "Only #{ALLOWED_ADVISOR_ROLES.join(', ')} can be granted to an advisor.",
                    fix: "Edit the advisor and pick roles from the allowed list." }
                end
    end

    if permissions.empty?
      issues << { severity: :blocker,
                  summary: "No modules are enabled for #{entity_label}",
                  detail: "Once switched into #{entity_label} the advisor's menu comes from this grant, and nothing " \
                          "is ticked - so they will land on an empty app.",
                  fix: "Edit this advisor and enable the modules they need (Documents, Funds, Investors, ...)." }
    end

    if AccessRight.where(entity_id:, user_id:).none?
      issues << { severity: :warning,
                  summary: "Nothing has been shared with the advisor at #{entity_label}",
                  detail: "They can switch in, but no funds, deals or documents have been assigned to them, so the " \
                          "screens will look empty.",
                  fix: "Open the relevant fund or deal at #{entity_label} and grant this advisor access to it." }
    end

    issues
  end

  def entity_label
    entity&.name || "entity #{entity_id}"
  end

  after_destroy :remove_access_rights
  def remove_access_rights
    AccessRight.where(entity_id:, user_id:).find_each(&:destroy)
    InvestorAccess.where(investor_entity_id: entity_id, email:).delete_all
  end

  # Set by import_upload, to indicate where this advisor was added
  attr_accessor :owner_name

  # refresh_user_cache callback removed: live DB queries in ApplicationPolicy replace the cache.
  after_create :notify_investor_team
  def notify_investor_team
    entity.employees.active.company_admins.each do |employee|
      InvestorAdvisorNotifier.with(record: self, entity_id:, owner_name:, email_method: :notify_investor_advisor_addition, msg: "Investor Advisor #{user.full_name} has been added").deliver_later(employee)
    end
  end
end
