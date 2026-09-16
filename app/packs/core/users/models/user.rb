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
  NOTIFICATION_TAGS = %w[Kpi Tasks db_dump_notification].freeze

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

  def investor_advisor
    @inv_adv ||= entity.investor_advisors.where(user_id: id).first
    @inv_adv
  end

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
