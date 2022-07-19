# == Schema Information
#
# Table name: users
#
#  id                     :integer          not null, primary key
#  first_name             :string(255)
#  last_name              :string(255)
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  email                  :string(255)      default(""), not null
#  encrypted_password     :string(255)      default(""), not null
#  reset_password_token   :string(255)
#  reset_password_sent_at :datetime
#  remember_created_at    :datetime
#  phone                  :string(100)
#  active                 :boolean          default("1")
#  confirmation_token     :string(255)
#  confirmed_at           :datetime
#  confirmation_sent_at   :datetime
#  entity_id              :integer
#  deleted_at             :datetime
#  system_created         :boolean          default("0")
#  sign_in_count          :integer          default("0"), not null
#  current_sign_in_at     :datetime
#  last_sign_in_at        :datetime
#  current_sign_in_ip     :string(255)
#  last_sign_in_ip        :string(255)
#  accept_terms           :boolean          default("0")
#  whatsapp_enabled       :boolean          default("0")
#  sale_notification      :boolean          default("0")
#  curr_role              :string(20)
#  permissions            :integer          default("0"), not null
#

class User < ApplicationRecord
  include PublicActivity::Model

  tracked except: :update, owner: proc { |controller, _model| controller.current_user if controller && controller.current_user },
          entity_id: proc { |controller, _model| controller.current_user.entity_id if controller && controller.current_user }

  has_many :activities, as: :trackable, class_name: 'PublicActivity::Activity', dependent: :destroy
  has_many :holdings, dependent: :destroy
  has_many :offers, dependent: :destroy
  has_many :interests, dependent: :destroy
  has_many :excercises, dependent: :destroy

  # Make all models searchable
  update_index('user') { self }

  rolify
  flag :permissions, %i[read_investor write_investor read_document write_document read_investment write_investment read_deal write_deal read_option_pool write_option_pool read_holding write_holding read_funding_round write_funding_round read_secondary_sale write_secondary_sale read_offer write_offer read_interest write_interest read_user write_user]

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable, :trackable,
         :recoverable, :rememberable, :validatable, :confirmable

  # Only if this user is an employee of the entity
  belongs_to :entity, optional: true

  validates :first_name, :last_name, presence: true
  validates :email, format: { with: /\A[^@\s]+@[^@\s]+\z/ }, presence: true

  before_create :setup_defaults
  after_create :update_investor_access

  delegate :name, to: :entity, prefix: :entity

  def to_s
    full_name
  end

  def name
    full_name
  end

  def full_name
    "#{first_name} #{last_name}"
  end

  def setup_defaults
    if entity
      if entity.entity_type == "Startup"
        add_role :startup
        add_role :holding
        self.curr_role = :startup
      elsif entity.entity_type == "Holding"
        add_role :holding
        self.curr_role = :holding
      elsif entity.entity_type == "VC" || InvestorAccess.where(user_id: id).first.present?
        add_role :secondary_buyer
        add_role :investor
        self.curr_role ||= :investor
      elsif ["Advisor", "Family Office"].include?(entity.entity_type)
        add_role :secondary_buyer
        self.curr_role = :secondary_buyer
      elsif entity.entity_type == "Angel Network"
        add_role :angel
        self.curr_role = :angel
      end
    else
      self.curr_role ||= :user
    end

    self.active = true
    # self.permissions = User.permissions.keys
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
    add_role :secondary_buyer if entity && (entity.entity_type == "VC")
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
end
