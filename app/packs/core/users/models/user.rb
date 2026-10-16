class User < ApplicationRecord
  include UserEnabled
  include WithCustomField
  include Memoized
  # AccessRightsCache removed: permission checks now use live DB queries (ApplicationPolicy)
  # instead of the serialized access_rights_cache column on users.
  include CanonicalFingerprint
  include TwoFactorAuthenticatable
  # Phone-number normalisation and SMS eligibility for the SMS two-factor mode.
  # Kept separate from TwoFactorAuthenticatable because it is about the number, not
  # about codes. See docs/modules/two_factor_auth/twilio_sms_otp_design.md.
  include SmsDeliverable

  include Trackable.new(on: %i[create update], audit_fields: %i[first_name last_name email phone permissions extended_permissions two_factor_mode])

  # SECURITY (finding M1): purpose scope shared by every passwordless-login signed_id — the email
  # magic link, the WhatsApp login link, and the no_password_login verification. Minting and
  # verifying with the SAME purpose ensures a User#signed_id created for any other reason cannot be
  # redeemed as a login. Keep this constant as the single source of truth for all three call sites.
  MAGIC_LINK_PURPOSE = :magic_login

  # tag_list is free text, but these values are checked for by exact string match elsewhere:
  # "Kpi" gates recipients for KpiReport's submission/failure notifiers (notify_fund_of_submission!,
  # reopen_after_failed_import! in app/packs/startups/kpis/models/kpi_report.rb, and the matching
  # controller path in kpi_reports_controller.rb#notify_fund_on_submission); "db_dump_notification"
  # gates recipients in EntityDbDumpJob; "Tasks" gates recipients for the weekly task digest
  # (WeeklyTaskDigestJob::RECIPIENT_TAG). Suggested (not enforced) on the user form's tag input —
  # other tags remain valid, e.g. per-entity Support Agent "notify_tag" config values.
  # "FundAccounting" gates recipients of FinancialStatementNotifier (FinancialStatementUnlockGuard::RECIPIENT_TAG).
  # "FundOps", "FundAccounting" and "Compliance" pick recipients for evergreen fund alerts (EvergreenRecipients).
  NOTIFICATION_TAGS = %w[Kpi Tasks db_dump_notification FundOps FundAccounting Compliance].freeze

  attr_accessor :role_name
  # This is set from session[:support_user_id] in the ApplicationController.
  # The session is setup in users_controller#no_password_login when support user logs in as another user
  attr_accessor :support_user_id

  scope :with_tag, lambda { |tag|
    where("tag_list LIKE ?", "%#{tag}%")
  }

  scope :with_any_tags, lambda { |tags|
    return none if tags.blank?

    tag_list = tags.split(",").map(&:strip).compact_blank
    return none if tag_list.empty?

    patterns = tag_list.map { |t| "%#{ActiveRecord::Base.sanitize_sql_like(t)}%" }
    clauses  = Array.new(patterns.length, "tag_list LIKE ?").join(" OR ")

    where(clauses, *patterns)
  }

  before_validation :normalize_tag_list

  # Normalize the tag list to be a comma separated string with no duplicates or blanks
  def normalize_tag_list
    normalized = tag_list
                 .to_s
                 .split(",")
                 .map(&:strip)
                 .compact_blank
                 .uniq
                 .join(",")

    self.tag_list = normalized.presence
  end

  # Returns an array of tags
  def tags
    tag_list.present? ? tag_list.to_s.split(",").map(&:strip).compact_blank : []
  end

  attribute :preferences, :json, default: {}

  # Returns the ordered list of dashboard names for a given dashboard_type from user preferences.
  # Stored as preferences["dashboard"][dashboard_type]["sequence"] = "D1,D2,D3"
  def dashboard_sequence(dashboard_type)
    Array(preferences&.dig("dashboard", dashboard_type, "sequence")
                     &.split(",")
                     &.map(&:strip)
                     &.compact_blank)
  end

  def support_user
    @support_user ||= User.find(support_user_id) if support_user_id.present?
    @support_user
  end

  # Get the initials of the user from the first and last name
  def initials
    "#{first_name[0].upcase}#{last_name[0].upcase}"
  end

  # Keep this in sync with the role list offered in _form.html.erb's roles select — any name
  # listed here that isn't also offered there (e.g. the old "signatory" entry) gets silently
  # removed from every user a company admin saves, since UsersController#update treats "not
  # present in the submitted role_name list" as "remove this role".
  UPDATABLE_ROLES = %w[company_admin approver employee].freeze
  CALL_CODES = {
    "in" => "91",
    "us" => "1",
    "uae" => "971",
    "sg" => "65",
    "tz" => "255",
    "ug" => "256",
    "nl" => "31",
    "ch" => "41",
    "uk" => "44",
    "au" => "61",
    "hk" => "852",
    "kw" => "965",
    "sa" => "966",
    "qa" => "974"
  }.freeze

  # Site-aware default dial code for new users, overriding the "91" schema default. Keyed
  # off CURRENT_SITE, the per-country deployment marker already used for SMS/user-sync and
  # FY month offset (see SmsDeliverable, EntitySetting) — US server defaults to "1", IN and
  # any other/blank value keep the pre-existing "91" default.
  attribute :call_code, :string, default: -> { geo_default_call_code }

  def self.geo_default_call_code
    case ENV.fetch("CURRENT_SITE", "").strip.upcase
    when "US" then "1"
    else "91"
    end
  end

  # The regions this user may actually be handed off to: what their profile says, canonicalised,
  # intersected with what is actually deployed.
  #
  # Both halves matter. `regions` is a free-text string edited through the Administrate user
  # dashboard, so it arrives as "IN,US", " in ,US, us" or even the JSON array '["US","IN"]' that
  # the multi-region sync writes - CanonicalFingerprint#normalize_regions_array already knows all
  # three shapes, so we reuse it rather than splitting on "," again here (splitting was how the
  # selector produced option values like `"US"]`). The intersection with SiteRegistry.codes keeps
  # a stale or misspelled code - "SG" on a deployment that has no SG - out of the selector
  # WITHOUT deleting it from the user's profile.
  #
  # This is both what the selector renders and what UserPolicy#cross_site_link? authorises
  # against, so the two can no longer disagree about which regions a user has.
  def switchable_region_codes
    normalize_regions_array(regions).select { |code| SiteRegistry.known?(code) }.sort
  rescue SiteRegistry::ConfigurationError
    # A misconfigured registry must not take out every page that renders the top bar; the boot
    # check is what is responsible for shouting about it.
    []
  end

  has_many :faq_threads, dependent: :destroy
  has_many :offers, dependent: :destroy
  has_many :interests, dependent: :destroy
  has_many :investor_accesses, dependent: :destroy
  has_many :access_rights, dependent: :destroy
  has_many :investment_criteria_templates, foreign_key: :created_by_user_id, dependent: :nullify

  # Noticed gem
  has_many :notifications, as: :recipient, dependent: :destroy, class_name: "Noticed::Notification"
  has_many :favorites, dependent: :destroy

  include FileUploader::Attachment(:signature)

  # Make all models searchable
  update_index('user') { self if index_record? }

  rolify before_add: :forbid_bad_role
  accepts_nested_attributes_for :roles, allow_destroy: true

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable, :trackable,
         :recoverable, :rememberable, :validatable, :lockable, :api,
         :two_factor_authenticatable

  # Override Devise::Models::Trackable to ensure the sign-in tracking
  # writes (sign_in_count, current_sign_in_at, etc.) always go to the
  # primary database. Without this, GET requests routed to the read
  # replica by the DatabaseSelector middleware raise ReadOnlyError when
  # Devise re-authenticates a user via the remember-me cookie.
  def update_tracked_fields!(request)
    return if new_record?

    update_tracked_fields(request)
    ActiveRecord::Base.connected_to(role: :writing) do
      save(validate: false)
    end
  end

  # Only if this user is an employee of the entity
  belongs_to :entity
  belongs_to :advisor_entity, class_name: "Entity", optional: true
  has_many :investor_advisors, dependent: :destroy
  has_many :investor_advisor_investors, class_name: "Investor", through: :investor_advisors, source: :investors

  validates :first_name, :last_name, presence: true

  validates :email, format: { with: /\A[^@\s]+@[^@\s]+\z/ }, presence: true
  validates :call_code, presence: true, if: -> { phone.present? }
  validates :phone, length: { maximum: 100 }
  normalizes :phone, with: ->(phone) { phone.delete("^0-9") }

  # Machine-driven writers set this to bypass phone_must_be_dialable.
  #
  # The validation is a data-entry guard for a human at a form, and only that. Two paths
  # mirror a number from a source they do not control and must never refuse it:
  #
  #   * UsersSyncController — the origin region is authoritative. Refusing the payload
  #     returns 422 and never stamps last_synced_ccf_hex, so the sender retries the same
  #     payload forever and that user's replication is permanently stuck.
  #   * InvestorAccess#update_user — builds the portal user from an access row (often
  #     imported from a spreadsheet). investor_accesses.user_id is nullable and the
  #     belongs_to autosave discards a failed save, so a refusal there silently produces
  #     an access row with no user rather than an error anyone sees.
  #
  # Both accepted any number before this validation existed; the flag keeps them exactly
  # as they were rather than making them the first casualties of a form-level rule.
  attr_accessor :skip_phone_validation

  # Only when the number is actually being touched.
  #
  # A bare `validates` would be the obvious thing and is the wrong thing: a fifth of the
  # rows already hold numbers that cannot be parsed (too short, or carrying their own
  # country code so that call_code gets prepended a second time), and validating them
  # unconditionally would block every unrelated edit — a role change, a permission
  # toggle — on a user whose phone column someone else got wrong years ago. Editing the
  # number is the one moment where the person saving can both see the problem and fix it.
  #
  # Skipped when call_code is blank so the presence validation above owns that message
  # rather than both firing at once.
  validate :phone_must_be_dialable,
           if: lambda {
             !skip_phone_validation && phone.present? && call_code.present? &&
               (phone_changed? || call_code_changed?)
           }

  validates :curr_role, :dept, length: { maximum: 20 }
  validates :entity_type, length: { maximum: 25 }
  validates :call_code, length: { maximum: 3 }
  validates :advisor_entity_roles, length: { maximum: 100 }, allow_blank: true

  scope :support_users, -> { joins(:roles).where("roles.name =?", "support") }
  scope :super_users, -> { joins(:roles).where("roles.name =?", "super") }
  scope :investor_advisor_roles, -> { joins(:roles).where("roles.name =?", "investor_advisor") }
  scope :company_admins, -> { joins(:roles).where("roles.name =?", "company_admin") }
  scope :not_investor_advisor_roles, -> { where(advisor_entity_id: nil) }
  scope :syncable, -> { where.not(primary_region: [nil, ""]) }
  scope :active, -> { where(active: true) }

  before_create :setup_defaults
  after_create :update_investor_access
  after_update :sync_investor_access_contact_details, if: :sync_investor_access_contact_details?
  before_save :update_kanban_permissions

  def update_kanban_permissions
    permissions.set(:enable_kanban) if permissions.enable_deals?
  end

  # Updates the 'enabled' state of all active SupportClientMappings for this user's entity.
  # This is triggered whenever the user's 'enable_support' attribute changes.
  # It ensures that all support client mappings that are currently active (not expired)
  # reflect the user's current support status.
  def update_support
    SupportClientMapping.where(entity_id:, end_date: Time.zone.today..).update_all(enabled: enable_support)
  end
  # rubocop:enable Rails/SkipsModelValidations

  delegate :name, to: :entity, prefix: :entity

  def to_s
    full_name
  end

  def phone_with_call_code
    "#{call_code}#{phone}"
  end

  # Dialable, not textable — landlines pass deliberately.
  #
  # `users.phone` is the contact number for the whole application, not just the SMS OTP
  # path: it feeds WhatsApp, notifications and the investor_access copy. Rejecting a
  # fixed line here would refuse legitimate data entry for users who will never use SMS
  # two-factor. A landline still fails SmsDeliverable#sms_available? and is simply never
  # offered the SMS mode.
  #
  # Uses the same parsed_phone as sms_available? so the form and the SMS gate cannot
  # disagree about what a usable number is.
  def phone_must_be_dialable
    return if parsed_phone&.valid?

    errors.add(:phone, "is not a valid phone number for country code +#{call_code}")
  end

  def name
    full_name
  end

  def full_name
    "#{first_name} #{last_name}"
  end

  def setup_defaults
    if entity.entity_type == "Company"
      Rails.logger.debug "Setting up company user"
      add_role :employee
      self.curr_role = :employee
    elsif ["Investor Advisor"].include?(entity.entity_type)
      Rails.logger.debug "Setting up investor advisor user"
      # This is specifically set for Investor Advisors. It is the orig entity_id of the advisor, and cannot change
      self.advisor_entity_id ||= entity_id
      self.advisor_entity_roles ||= "employee,investor_advisor"

      # Ensure that the advisor_entity_roles has the investor_advisor
      advisor_entity_roles_list = advisor_entity_roles.split(",").map(&:strip)
      unless advisor_entity_roles_list.include?("investor_advisor")
        advisor_entity_roles_list << "investor_advisor"
        self.advisor_entity_roles = advisor_entity_roles_list.join(",")
      end

      # Set the curr_role to the first role in the advisor_entity_roles
      self.curr_role = advisor_entity_roles_list[0]
      # Add this role to the user to ensure it is recognized as an advisor
      add_role :investor_advisor

    elsif entity.is_fund?
      Rails.logger.debug "Setting up fund user"
      add_role :employee
      self.curr_role = :employee
    elsif ["Investor", "Investment Advisor", "Family Office"].include?(entity.entity_type) || InvestorAccess.where(user_id: id).first.present?
      Rails.logger.debug "Setting up investor user"
      add_role :investor
      self.curr_role = :investor

      # Special handling for RMs
      if InvestorAccess.joins(:investor).where(user_id: id).where(investors: { category: "RM" }).first.present?
        # If the user has InvestorAccess with RM category, then add the RM role
        add_role :rm
      end
    end

    self.permissions = User.permissions.keys if permissions.blank?
    # self.extended_permissions = User.extended_permissions.keys if permissions.blank?
    self.entity_type = entity&.entity_type
    self.active = true
  end

  # There may be pending investor access given before the user is created.
  # Ensure those are updated with this users id
  def update_investor_access
    InvestorAccess.where(email:).update(user_id: id)
    ia = InvestorAccess.where(email:).first
    # Sometimes the invite goes out via the investor access, hence we need to associate the user to the entity
    if ia&.investor && entity_id.nil?
      # Set the users entity
      self.entity_id = ia.investor.investor_entity_id
    end
    add_role :investor if entity && (entity.entity_type == "Investor")
    save
  end

  def sync_investor_access_contact_details?
    saved_change_to_email? || saved_change_to_phone? || saved_change_to_call_code?
  end

  # InvestorAccess keeps its own copies of email/phone. call_code has no persisted column on
  # investor_accesses (dropped by db/migrate/archive/20260410113954_remove_extra_columns_from_db.rb;
  # it now only survives as a transient attr_accessor used at InvestorAccess creation time), so
  # there is nothing to write for it here even though it's part of the change we react to.
  #
  # Bypass validations/callbacks with update_all: InvestorAccess#update_user (before_validation)
  # would otherwise re-derive `user` from the new email via User.find_by(email:), which could
  # detach this investor_access from this user or spin up an unrelated new User. investor_accesses.phone
  # is capped shorter (15) than users.phone (100), so truncate defensively rather than risk a
  # DB-level "value too long" error aborting this user's save.
  def sync_investor_access_contact_details
    investor_accesses.update_all(email:, phone: phone.to_s[0, 15])
  end

  def send_devise_notification(notification, *)
    devise_mailer.send(notification, self, *).deliver_later
  end

  def investor_entity(entity_id)
    Entity.user_investor_entities(self).where('entities.id': entity_id).first
  end

  def investor(entity_id)
    Investor.includes(:entity).user_investors(self).where('entities.id': entity_id).first
  end

  def reset_password?
    sign_in_count == 1 && system_created
  end

  def employee_parent_entity
    entity.investees.first&.entity
  end

  def self.update_roles
    User.find_each do |u|
      if u.has_cached_role?(:company) || u.has_cached_role?(:fund_manager)
        u.remove_role(:company)
        u.remove_role(:fund_manager)
        u.add_role(:employee)
        u.curr_role = :employee
      end
      if u.has_cached_role?(:secondary_buyer)
        u.remove_role(:secondary_buyer)
        u.add_role(:investor)
        u.curr_role = :investor
      end

      u.entity_type = u.entity&.entity_type
      u.save
    end
  end

  def curr_role_investor?
    curr_role == "investor"
  end

  def curr_role_employee?
    curr_role == "employee"
  end

  # We only allow users to have the investor_advisor role if their advisor entity is of type "Investor Advisor"
  # This is a hard rule that cannot be overriden at this time
  def forbid_bad_role(role)
    # if advisor_entity&.entity_type != "Investor Advisor" && role.name.to_s == "investor_advisor"
    #   errors.add(:roles, "Cannot add investor_advisor role to a user whose 'advisor entity' is not an 'Investor Advisor'")
    #   throw :abort
    # end

    if ["super", :super].include?(role.name)
      errors.add(:roles, "Cannot add super role to a user")
      throw :abort
    end
  end

  def support?
    # Check if the user has the support role or is support impoersonating some user
    has_cached_role?(:support) || support_user_id.present?
  end

  def super?
    # Check if the user has the support role or is support impoersonating some user
    has_cached_role?(:super)
  end

  def company_admin?
    has_cached_role?(:company_admin)
  end

  # This checks that the user has currently switched to the investor advisor role
  def investor_advisor?
    advisor_entity_id.present? && advisor_entity_id != entity_id
  end

  # In-memory mirror of InvestorAdvisor.revert: a detached, read-only User configured exactly as
  # this advisor would be after reverting to his home entity — entity_id, entity_type, curr_role
  # and roles all come from the home persona (advisor_entity_id / advisor_entity_roles), nothing
  # is persisted. Returns nil unless the user is an advisor currently switched into a host entity.
  #
  # Used by Investor#notification_users to ask "would this contact see X in his own entity?"
  # without the answer depending on which host entity he happens to be switched into. Roles a
  # host entity granted on switch are deliberately dropped, so the persona can never see more
  # than the real user sees after pressing Revert — for policies that use has_cached_role?, which
  # is every policy reachable from the notification paths; the uncached has_role? (only the
  # ValidationRule policies) would still read the persisted, switched-in roles.
  def home_persona
    return nil unless has_cached_role?(:investor_advisor) && investor_advisor?

    # Memoized per switch state: notification loops call this once per record for the same user
    # object, and the persona costs three queries to build.
    key = [entity_id, advisor_entity_id, advisor_entity_roles]
    return @home_persona if @home_persona_key == key

    @home_persona_key = key
    @home_persona = build_home_persona
  end

  def build_home_persona
    # A deleted home entity: a real revert would raise in setup_defaults, so there is no home
    # persona to judge by (and curr_role_after_setup_defaults must not guess one).
    home = Entity.find_by(id: advisor_entity_id)
    return nil if home.nil?

    build_persona(home, investor_advisor_id: nil, role_names: home_role_names(home_entity_type: home.entity_type))
  end
  private :build_home_persona

  # In-memory mirror of InvestorAdvisor#switch(self) for this grant - the user as they would be
  # right after picking the grant in the persona dropdown: its entity, investor_advisor_id, the
  # grant's allowed roles plus investor_advisor (exactly what switch re-adds), and the curr_role
  # setup_defaults gives in that entity. Read-only and never saved, like #home_persona, so it can
  # only confirm what a real switch would allow. Used by the Access Denied hint to name the
  # client to switch into. Worked examples H8, E17, E18 —
  # openspec/changes/fix-advisor-own-investor-access/report.md#verification
  def switched_persona(grant)
    return nil if grant.entity.nil?

    build_persona(grant.entity, investor_advisor_id: grant.id,
                                role_names: (Array(grant.allowed_roles).map(&:to_s) + ["investor_advisor"]).uniq)
  end

  # Shared by both personas so the two can never be assembled differently.
  def build_persona(entity, investor_advisor_id:, role_names:)
    # A fresh instance rather than dup: dup clears the primary key and association cache, which
    # breaks has_cached_role? (see Investor#notification_users).
    persona = User.find(id)
    persona.entity = entity
    persona.entity_type = entity.entity_type
    persona.investor_advisor_id = investor_advisor_id
    persona.curr_role = curr_role_after_setup_defaults(entity)

    # switch / revert re-add these with add_role (find-or-create), so a role name with no Role row
    # yet must still count; an unsaved Role satisfies rolify's has_cached_role? lookup (it only
    # compares name/resource) without writing anything.
    existing_roles = Role.where(name: role_names, resource_type: nil, resource_id: nil).to_a
    missing_roles = (role_names - existing_roles.map(&:name)).map { |name| Role.new(name:) }
    roles_association = persona.association(:roles)
    roles_association.target = existing_roles + missing_roles
    roles_association.loaded!

    persona.readonly!
    persona
  end
  private :build_persona

  # The curr_role that setup_defaults sets in `entity` - which is what both InvestorAdvisor#switch
  # and InvestorAdvisor.revert leave behind (each runs setup_defaults, then only swaps roles).
  # Taking the first home role instead was only right for an "Investor Advisor" firm: for an
  # Investor-type home (prod user 2564) revert gives `investor` while the first home role is
  # `investor_advisor`, so the home persona failed the investor rule's curr_role check and the
  # advisor, switched into a client, missed notices for their own investment.
  # Worked examples E1, E9 — openspec/changes/fix-advisor-own-investor-access/report.md#verification
  # Keep the branches in step with setup_defaults; E9 compares the two.
  def curr_role_after_setup_defaults(entity)
    entity_type = entity.entity_type
    if entity_type == "Company" || entity.is_fund?
      "employee"
    elsif entity_type == "Investor Advisor"
      # setup_defaults: the first of advisor_entity_roles (defaulted, investor_advisor appended).
      home_role_names(home_entity_type: entity_type).first
    elsif ["Investor", "Investment Advisor", "Family Office"].include?(entity_type) || InvestorAccess.exists?(user_id: id)
      "investor"
    else
      # setup_defaults leaves curr_role alone for any other entity type.
      curr_role
    end
  end
  private :curr_role_after_setup_defaults

  # The roles this advisor holds in his home entity — exactly what InvestorAdvisor.revert re-adds.
  # setup_defaults forces investor_advisor into advisor_entity_roles for an "Investor Advisor"
  # entity, and revert adds it when the list is empty; both live here so the real revert and
  # User#home_persona cannot drift (an admin can store advisor_entity_roles without it).
  def home_role_names(home_entity_type: nil)
    names = advisor_entity_roles.to_s.split(",").map(&:strip).reject(&:empty?)
    home_entity_type ||= Entity.where(id: advisor_entity_id).pick(:entity_type)
    names << "investor_advisor" if names.empty? || home_entity_type == "Investor Advisor"
    names.uniq
  end

  def investor_advisor
    @inv_adv ||= entity.investor_advisors.where(user_id: id).first
    @inv_adv
  end

  # Is this account set up as an investor advisor at all? Used to decide whether the advisor
  # health check is worth showing on the user page.
  def investor_advisor_account?
    has_cached_role?(:investor_advisor) || InvestorAdvisor.with_deleted.exists?(user_id: id)
  end

  # Health check for an investor advisor account - the usual complaint is "I signed in but there
  # is no company switcher in the top bar".
  #
  #   User.check_investor_advisor("ops@example.com")   # prints a report
  #   user.check_investor_advisor
  #
  # Returns the issue list from #investor_advisor_setup_issues; empty means the setup is complete.
  def self.check_investor_advisor(email)
    user = with_deleted.find_by(email: email.to_s.strip)
    if user.nil?
      puts "No user with email #{email}" # rubocop:disable Rails/Output
      return nil
    end

    user.check_investor_advisor
  end

  # rubocop:disable Rails/Output -- a console report; stdout is the point
  def check_investor_advisor
    issues = investor_advisor_setup_issues
    home = Entity.find_by(id: advisor_entity_id)

    puts "User            #{id} #{email} (active=#{active}, deleted_at=#{deleted_at.inspect})"
    puts "Current entity  #{entity_id} #{entity&.name.inspect} type=#{entity&.entity_type.inspect}"
    puts "Home entity     #{advisor_entity_id.inspect} #{home&.name.inspect} type=#{home&.entity_type.inspect}"
    puts "advisor_entity_roles=#{advisor_entity_roles.inspect} curr_role=#{curr_role.inspect} " \
         "investor_advisor_id=#{investor_advisor_id.inspect}"
    puts "roles           #{roles.pluck(:name).inspect}"
    puts "switched in?    #{investor_advisor?}   company switcher shown? #{advisor_entity_id.present?}"
    puts "switcher lists  #{switchable_advisor_entities.pluck('entities.name').inspect}"

    if issues.empty?
      puts "\nOK - nothing blocking the company switcher."
    else
      puts "\n#{issues.size} issue(s):"
      issues.each do |issue|
        puts "\n  [#{issue[:severity].to_s.upcase}] #{issue[:summary]}"
        puts "        Why: #{issue[:detail]}"
        puts "        Fix: #{issue[:fix]}"
      end
    end

    issues
  end
  # rubocop:enable Rails/Output

  # The grants the topbar switcher would actually list, exactly as _personas.html.erb builds it.
  def switchable_advisor_entities
    InvestorAdvisor.joins(:entity).where(user_id: id).where(entities: { active: true })
  end

  # Every invariant an investor advisor needs, worst first. Each issue is a hash of
  #   { severity: :blocker | :warning, summary:, detail:, fix: }
  # phrased for whoever is looking at the user page, not for a developer.
  def investor_advisor_setup_issues
    issues = []

    if deleted_at.present?
      issues << { severity: :blocker,
                  summary: "This user account has been deleted",
                  detail: "Deleted accounts cannot sign in.",
                  fix: "Restore the account if this was a mistake." }
    end

    unless active
      issues << { severity: :blocker,
                  summary: "This user account is switched off",
                  detail: "Inactive users are not allowed to sign in.",
                  fix: "Set the user back to active." }
    end

    issues.concat(home_entity_issues)
    issues.concat(advisor_role_issues)

    if switchable_advisor_entities.none?
      hidden = InvestorAdvisor.with_deleted.where(user_id: id).count
      issues << if hidden.zero?
                  { severity: :blocker,
                    summary: "This advisor has not been given access to any company",
                    detail: "The switcher lists the companies that have added them as an advisor, and there are none.",
                    fix: "Ask the client company to add #{email} as an investor advisor." }
                else
                  { severity: :blocker,
                    summary: "None of this advisor's #{hidden} company grants can be used",
                    detail: "They have been deleted, or the companies themselves are deactivated, so the switcher " \
                            "has nothing to offer.",
                    fix: "See the individual grants below." }
                end
    end

    if investor_advisor? && entity.present? && investor_advisor.nil?
      issues << { severity: :warning,
                  summary: "This advisor is signed in to a company they have no grant for",
                  detail: "They are currently switched into #{entity&.name}, but no advisor grant exists there. " \
                          "Their menu will fall back to their own permissions instead of the ones meant for that company.",
                  fix: "Add an advisor grant for them at #{entity&.name}, or ask them to switch back to Self." }
    end

    InvestorAdvisor.with_deleted.where(user_id: id).includes(:entity).find_each do |grant|
      issues.concat(grant.setup_issues)
    end

    # each_with_index keeps the original order within a severity - Ruby's sort_by is not stable,
    # and the per-grant issues must stay grouped in the order they were gathered.
    issues.each_with_index.sort_by { |issue, i| [issue[:severity] == :blocker ? 0 : 1, i] }.map(&:first)
  end

  # The company switcher in the top bar appears only once the advisor's own firm is recorded on
  # the user (advisor_entity_id). That is written by setup_defaults, and only when the user's
  # company is of type "Investor Advisor" - which is why converting an existing user into an
  # advisor without moving them first leaves them with no switcher.
  def home_entity_issues
    return [home_entity_missing_issue] if advisor_entity_id.blank?

    home = Entity.find_by(id: advisor_entity_id)
    if home.nil?
      return [{ severity: :blocker,
                summary: "This advisor's own firm no longer exists",
                detail: "Their account points at company #{advisor_entity_id}, which is not in the system.",
                fix: "Set the user's company to their advisory firm and save, so it is recorded again." }]
    end

    issues = []
    unless home.entity_type == "Investor Advisor"
      issues << { severity: :warning,
                  summary: "#{home.name} is not set up as an advisory firm",
                  detail: "It is recorded as \"#{home.entity_type}\". The switcher works today, but if this user is " \
                          "ever saved again their advisor settings will not be rebuilt.",
                  fix: "Change #{home.name}'s company type to \"Investor Advisor\"." }
    end
    unless home.active?
      issues << { severity: :warning,
                  summary: "#{home.name}, this advisor's own firm, is deactivated",
                  detail: "They can still act for their clients, but their own company is switched off.",
                  fix: "Reactivate #{home.name} if that was not intended." }
    end
    issues
  end

  def home_entity_missing_issue
    if entity&.entity_type == "Investor Advisor"
      { severity: :blocker,
        summary: "No company switcher in the top bar",
        detail: "This advisor's own firm is not recorded on their account, and the switcher only appears once it " \
                "is. Their company #{entity.name} is already an advisory firm, so this was simply never filled " \
                "in - it happens when an existing user is made an advisor after their account was created.",
        fix: "In the Rails console: u = User.find(#{id}); u.setup_defaults; u.save! - then ask them to sign in again." }
    else
      { severity: :blocker,
        summary: "No company switcher in the top bar",
        detail: "This advisor's own firm is not recorded on their account, and the switcher only appears once it " \
                "is. They currently belong to #{entity&.name || 'no company'}" \
                "#{" (#{entity.entity_type})" if entity&.entity_type}, which is not an advisory firm, so the " \
                "setting was never filled in.",
        fix: "Create their advisory firm as a company of type \"Investor Advisor\", move this user into it, and " \
             "save - then ask them to sign in again." }
    end
  end

  def advisor_role_issues
    issues = []

    unless has_cached_role?(:investor_advisor)
      issues << { severity: :blocker,
                  summary: "This user is not marked as an investor advisor",
                  detail: "Without that, client companies cannot add them as an advisor and the switch is refused.",
                  fix: "Give the user the investor advisor role." }
    end

    # home_role_names only forces investor_advisor back in when the list is empty or the home
    # company is an "Investor Advisor" - otherwise a Revert silently drops the role.
    stored_roles = advisor_entity_roles.to_s.split(",").map(&:strip).reject(&:empty?)
    if advisor_entity_id.present? && stored_roles.any? && stored_roles.exclude?("investor_advisor") &&
       Entity.where(id: advisor_entity_id).pick(:entity_type) != "Investor Advisor"
      issues << { severity: :warning,
                  summary: "Switching back to Self would remove this user's advisor status",
                  detail: "The roles kept for their own firm (#{stored_roles.join(', ')}) do not include investor " \
                          "advisor, so pressing Self would leave them unable to switch back out again.",
                  fix: "Add investor_advisor to the user's advisor_entity_roles." }
    end

    if entity && entity_type != entity.entity_type
      issues << { severity: :warning,
                  summary: "This user's recorded company type is out of date",
                  detail: "The account says \"#{entity_type}\" but #{entity.name} is a \"#{entity.entity_type}\". " \
                          "Some screens pick what to show from this.",
                  fix: "In the Rails console: u = User.find(#{id}); u.setup_defaults; u.save!" }
    end

    issues
  end
  private :home_entity_issues, :home_entity_missing_issue, :advisor_role_issues

  # Security fix (Finding 7 — redirect_to phishing): redirect_to parameter removed.
  # The magic link email must not embed a caller-supplied redirect destination.
  # After authentication, the destination is determined solely from session[:user_return_to]
  # server-side in UsersController#no_password_login. See that action for the full rationale.
  def send_magic_link(current_entity_id)
    UserMailer.with(id:, current_entity_id:).magic_link.deliver_later
  end

  def show_all_cols?
    entity_type == "Group Company"
  end

  # validate :password_complexity
  # Not used yet
  def password_complexity
    # Regexp extracted from https://stackoverflow.com/questions/19605150/regex-for-password-must-contain-at-least-eight-characters-at-least-one-number-a
    return if password.blank? || password =~ /(?=.*?[A-Z])(?=.*?[a-z])(?=.*?[0-9])(?=.*?[#?!@$%^&*-])/

    errors.add :password, 'Complexity requirement not met. Please use: 1 uppercase, 1 lowercase, 1 digit and 1 special character'
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[first_name last_name email phone whatsapp_enabled two_factor_enabled advisor_entity_id].sort
  end

  def active_for_authentication?
    super && active
  end

  def custom_dashboard
    if entity.entity_setting.custom_dashboards.present?
      entity.entity_setting.custom_dashboards.split(";").each do |dashboard_role|
        dashboard, role = dashboard_role.split(":")
        next unless role == curr_role || role.nil?

        return dashboard
      end
    end
  end

  def set_persona(curr_role)
    self.curr_role = curr_role if has_cached_role?(curr_role.to_sym)
    save
  end

  # rubocop:disable Rails/SkipsModelValidations
  def self.disable_support_for_all
    User.where(enable_support: true).update_all(enable_support: false)
  end
  # rubocop:enable Rails/SkipsModelValidations

  before_save :generate_session_token
  def generate_session_token
    self.session_token ||= SecureRandom.hex(64)
  end

  def self.msg_todays_users(message, level: :info)
    User.where(current_sign_in_at: Time.zone.now.beginning_of_day..).find_each do |user|
      UserAlert.new(user_id: user.id, message:, level:).broadcast
    end
  end
end
