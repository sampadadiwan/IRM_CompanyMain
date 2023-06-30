class User < ApplicationRecord
  include PublicActivity::Model
  include UserEnabled

  attr_accessor :role_name

  UPDATABLE_ROLES = %w[company_admin approver signatory].freeze
  CALL_CODES = {
    "in" => "91",
    "us" => "1",
    "uae" => "971",
    "sg" => "65"
  }.freeze

  tracked except: :update, owner: proc { |controller, _model| controller.current_user if controller && controller.current_user },
          entity_id: proc { |controller, _model| controller.current_user.entity_id if controller && controller.current_user }

  has_many :activities, as: :trackable, class_name: 'PublicActivity::Activity', dependent: :destroy
  has_many :holdings, dependent: :destroy
  has_many :offers, dependent: :destroy
  has_many :interests, dependent: :destroy
  has_many :excercises, dependent: :destroy
  has_many :investor_accesses, dependent: :destroy

  include FileUploader::Attachment(:signature)

  # Make all models searchable
  update_index('user') { self }

  rolify
  accepts_nested_attributes_for :roles, allow_destroy: true

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable, :trackable,
         :recoverable, :rememberable, :validatable, :confirmable

  # Only if this user is an employee of the entity
  belongs_to :entity
  belongs_to :advisor_entity, class_name: "Entity", optional: true

  validates :first_name, :last_name, presence: true
  validates :email, format: { with: /\A[^@\s]+@[^@\s]+\z/ }, presence: true
  validates :call_code, presence: true, if: -> { phone.present? }
  validates :phone, length: { maximum: 100 }
  validates :curr_role, :dept, length: { maximum: 20 }
  validates :entity_type, length: { maximum: 25 }
  validates :call_code, length: { maximum: 3 }

  before_create :setup_defaults
  after_create :update_investor_access
  before_save :confirm_user, if: :password_changed?
  def confirm_user
    confirm unless confirmed?
  end
  # using before_save as after_save,after_commit,after_update all returned false for encrypted_password_changed?
  before_save :send_password_update_notification, if: :password_changed?

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
    elsif ["Investor", "Investment Advisor", "Family Office"].include?(entity.entity_type) || InvestorAccess.where(user_id: id).first.present?
      add_role :investor
      self.curr_role ||= :investor
    elsif ["Investor Advisor"].include?(entity.entity_type)
      add_role :investor
      add_role :investor_advisor
      self.curr_role ||= :investor
      # This is specifically set for Investor Advisors. It is the orig entity_id of the advisor, and cannot change
      self.advisor_entity_id = entity_id
    elsif ["Investment Fund", "Group Company"].include?(entity.entity_type)
      add_role :employee
      self.curr_role = :employee
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

  def send_devise_notification(notification, *args)
    devise_mailer.send(notification, self, *args).deliver_later
  end

  def investor_entity(entity_id)
    Entity.user_investor_entities(self).where('entities.id': entity_id).first
  end

  def investor(entity_id)
    Investor.includes(:entity).user_investors(self).where('entities.id': entity_id).first
  end

  def active_for_authentication?
    active && !confirmed_at.nil?
  end

  def reset_password?
    sign_in_count == 1 && system_created
  end

  def employee_parent_entity
    entity.investees.first&.entity
  end

  def self.update_roles
    User.all.each do |u|
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

  private

  def send_password_update_notification
    WhatsappNotifier.new.perform({ template_name: ENV.fetch('ACC_UPDATE_NOTI_TEMPLATE') }.stringify_keys, self)
  rescue StandardError => e # added rescue because if error is raised in before_save callback then the record wont get saved
    Rails.logger.error "Error in sending whatsapp notification, #{e}"
  end
end
