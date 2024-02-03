class User < ApplicationRecord
  include PublicActivity::Model
  include UserEnabled
  include WithCustomField

  # include Trackable
  audited only: %i[first_name last_name email phone permissions extended_permissions]
  acts_as_paranoid

  attr_accessor :role_name

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

  tracked except: :update, owner: proc { |controller, _model| controller.current_user if controller && controller.current_user },
          entity_id: proc { |controller, _model| controller.current_user.entity_id if controller && controller.current_user }

  has_many :activities, as: :trackable, class_name: 'PublicActivity::Activity', dependent: :destroy
  has_many :holdings, dependent: :destroy
  has_many :offers, dependent: :destroy
  has_many :interests, dependent: :destroy
  has_many :excercises, dependent: :destroy
  has_many :investor_accesses, dependent: :destroy

  # Noticed gem
  has_many :notifications, as: :recipient, dependent: :destroy

  include FileUploader::Attachment(:signature)

  # Make all models searchable
  update_index('user') { self if index_record? }

  rolify
  accepts_nested_attributes_for :roles, allow_destroy: true

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable, :trackable,
         :recoverable, :rememberable, :validatable, :confirmable, :lockable

  # Only if this user is an employee of the entity
  belongs_to :entity
  belongs_to :advisor_entity, class_name: "Entity", optional: true

  validates :first_name, :last_name, presence: true
  validates :email, format: { with: /\A[^@\s]+@[^@\s]+\z/ }, presence: true
  validates :call_code, presence: true, if: -> { phone.present? }
  validates :phone, length: { maximum: 100 }
  normalizes :phone, with: ->(phone) { phone.delete("^0-9") }

  validates :curr_role, :dept, length: { maximum: 20 }
  validates :entity_type, length: { maximum: 25 }
  validates :call_code, length: { maximum: 3 }

  before_create :setup_defaults
  after_create :update_investor_access
  before_save :confirm_user, if: :password_changed?
  def confirm_user
    confirm unless confirmed?
  end

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
      add_role :employee
      add_role :holding
      self.curr_role = :employee
    elsif entity.entity_type == "Holding"
      add_role :holding
      self.curr_role = :holding
    elsif ["Investor Advisor"].include?(entity.entity_type)
      add_role :employee
      add_role :investor_advisor
      self.curr_role = :employee
      # This is specifically set for Investor Advisors. It is the orig entity_id of the advisor, and cannot change
      self.advisor_entity_id = entity_id
    elsif entity.is_fund?
      add_role :employee
      self.curr_role = :employee
    elsif ["Investor", "Investment Advisor", "Family Office"].include?(entity.entity_type) || InvestorAccess.where(user_id: id).first.present?
      add_role :investor
      self.curr_role = :investor
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
    if ia && (ia.investor && entity_id.nil?)
      # Set the users entity
      self.entity_id = ia.investor.investor_entity_id
    end
    # Add this role so we can identify which users have holdings
    add_role :holding if entity && (entity.entity_type == "Holding")
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

  def investor_advisor?
    advisor_entity_id.present? && advisor_entity_id != entity_id
  end

  def investor_advisor
    entity.investor_advisors.where(user_id: id).first
  end

  def send_magic_link
    UserMailer.with(id:).magic_link.deliver_later
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
    %w[first_name last_name email phone whatsapp_enabled].sort
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
end
