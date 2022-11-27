class Fund < ApplicationRecord
  include FundCalcs
  include WithFolder
  include ActivityTrackable
  tracked owner: proc { |_controller, model| model }, entity_id: proc { |_controller, model| model.entity_id }

  belongs_to :entity, touch: true
  belongs_to :funding_round
  belongs_to :fund_signatory, class_name: "User", optional: true
  belongs_to :trustee_signatory, class_name: "User", optional: true

  has_many :documents, as: :owner, dependent: :destroy
  has_many :valuations, as: :owner, dependent: :destroy
  has_many :capital_remittances, dependent: :destroy
  has_many :capital_commitments, dependent: :destroy
  has_many :capital_distributions, dependent: :destroy
  has_many :capital_distribution_payments, dependent: :destroy
  has_many :capital_calls, dependent: :destroy
  has_many :access_rights, as: :owner, dependent: :destroy

  belongs_to :form_type, optional: true
  serialize :properties, Hash

  monetize :call_amount_cents, :committed_amount_cents, :collected_amount_cents, :distribution_amount_cents, with_currency: ->(i) { i.entity.currency }

  validates :name, presence: true

  before_validation :setup_funding_round
  def setup_funding_round
    self.funding_round = FundingRound.new(name:, entity_id:, status: "Open", currency: entity.currency)
  end

  def folder_path
    "/Funds/#{name}-#{id}"
  end

  def setup_folder_details
    setup_folder_from_path(folder_path)
  end

  def investors
    investor_list = []
    access_rights.not_user.includes(:investor).find_each do |ar|
      investor_list += ar.investors
    end
    investor_list.uniq
  end

  scope :for_employee, lambda { |user|
    includes(:access_rights).joins(:access_rights).where("funds.entity_id=? and access_rights.user_id=?", user.entity_id, user.id)
  }

  scope :for_advisor, lambda { |user|
    # Ensure the access rghts for Document
    includes(:access_rights).joins(:access_rights).merge(AccessRight.access_filter)
                            .where("access_rights.metadata=?", "Advisor").joins(entity: :investors)
                            .where("investors.investor_entity_id=?", user.entity_id)
  }

  scope :for_investor, lambda { |user|
    # Ensure the access rghts for Document
    joins(:access_rights)
      .merge(AccessRight.access_filter)
      .joins(entity: :investors)
      # Ensure that the user is an investor and tis investor has been given access rights
      # .where("entities.id=?", entity.id)
      .where("investors.investor_entity_id=?", user.entity_id)
      # Ensure this user has investor access
      .joins(entity: :investor_accesses)
      .merge(InvestorAccess.approved_for_user(user))
  }

  def to_s
    name
  end

  def mkdirs
    # dirs = ["funds", "capital_calls", "capital_commitments", "capital_distributions", "capital_distribution_payments", "capital_remittances"]

    # dirs = ["access_rights", "documents", "entities", "folders", "notes", "permissions", "reminders", "tasks", "users", "investors", "investor_accesses"]

    subs = %w[models controllers views jobs policies mailers helpers]

    dirs.each do |dir|
      FileUtils.mkdir_p "app/packs/funds/#{dir}"
      subs.each do |sub|
        FileUtils.mkdir_p "app/packs/funds/#{dir}/#{sub}"
      end
    end
  end

  def document_tags
    ["Template", "Fund Document"]
  end

  def advisor_users
    investor_users("Advisor")
  end

  def investor_users(metadata)
    User.joins(investor_accesses: :investor).where("investor_accesses.approved=? and investor_accesses.entity_id=?", true, entity_id).merge(Investor.owner_access_rights(self, metadata))
  end
end
