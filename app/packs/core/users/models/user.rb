class User < ApplicationRecord
  include UserEnabled
  include WithCustomField
  include Memoized
  include AccessRightsCache

  acts_as_favoritor

  include Trackable.new(on: %i[create update], audit_fields: %i[first_name last_name email phone permissions extended_permissions])

  attr_accessor :role_name
  # This is set from session[:support_user_id] in the ApplicationController.
  # The session is setup in users_controller#no_password_login when support user logs in as another user
  attr_accessor :support_user_id

  def support_user
    @support_user ||= User.find(support_user_id) if support_user_id.present?
    @support_user
  end

  # Get the initials of the user from the first and last name
  def initials
    "#{first_name[0].upcase}#{last_name[0].upcase}"
  end

  UPDATABLE_ROLES = %w[company_admin approver signatory].freeze
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

  has_many :offers, dependent: :destroy
  has_many :interests, dependent: :destroy
  has_many :investor_accesses, dependent: :destroy

  # Noticed gem
  has_many :notifications, as: :recipient, dependent: :destroy, class_name: "Noticed::Notification"

  include FileUploader::Attachment(:signature)

  # Make all models searchable
  update_index('user') { self if index_record? }

  rolify before_add: :forbid_bad_role
  accepts_nested_attributes_for :roles, allow_destroy: true

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable, :trackable,
         :recoverable, :rememberable, :validatable, :confirmable, :lockable, :api

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

  validates :curr_role, :dept, length: { maximum: 20 }
  validates :entity_type, length: { maximum: 25 }
  validates :call_code, length: { maximum: 3 }

  scope :support_users, -> { joins(:roles).where("roles.name =?", "support") }
  scope :super_users, -> { joins(:roles).where("roles.name =?", "super") }
  scope :investor_advisor_roles, -> { joins(:roles).where("roles.name =?", "investor_advisor") }
  scope :not_investor_advisor_roles, -> { where(advisor_entity_id: nil) }

  before_create :setup_defaults
  after_create :update_investor_access
  before_save :confirm_user, if: :password_changed?
  before_save :update_kanban_permissions

  def confirm_user
    confirm unless confirmed?
  end

  def update_kanban_permissions
    permissions.set(:enable_kanban) if permissions.enable_deals?
  end

  # Ensure that support gets enabled if a mapping is already there.
  before_save :update_support, if: :enable_support_changed?
  # rubocop:disable Rails/SkipsModelValidations
  def update_support
    SupportClientMapping.where(entity_id:).update_all(enabled: enable_support, end_date: Time.zone.today + 1.day)
  end
  # rubocop:enable Rails/SkipsModelValidations

  def password_changed?
    encrypted_password_changed? && persisted?
  end

  delegate :name, to: :entity, prefix: :entity

  def to_s
    full_name
  end

  def phone_with_call_code
    "#{call_code}#{phone}"
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

      add_role :employee
      self.curr_role = :employee
      # Add this role to the user to ensure it is recognized as an advisor
      add_role :investor_advisor

      # Ensure that the advisor_entity_roles has the investor_advisor
      advisor_entity_roles_list = advisor_entity_roles.split(",").map(&:strip)
      unless advisor_entity_roles_list.include?("investor_advisor")
        advisor_entity_roles_list << "investor_advisor"
        self.advisor_entity_roles = advisor_entity_roles_list.join(",")
      end
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
    if advisor_entity&.entity_type != "Investor Advisor" && role.name.to_s == "investor_advisor"
      errors.add(:roles, "Cannot add investor_advisor role to a user whose 'advisor entity' is not an 'Investor Advisor'")
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

  def send_magic_link(current_entity_id, redirect_to)
    UserMailer.with(id:, current_entity_id:, redirect_to:).magic_link.deliver_later
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
    %w[first_name last_name email phone whatsapp_enabled advisor_entity_id].sort
  end

  def active_for_authentication?
    super && active && entity.active
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
