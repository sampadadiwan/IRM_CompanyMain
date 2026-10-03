class Investor < ApplicationRecord
  include WithCustomField
  include Trackable.new
  include UpdateInvestor
  include WithFolder
  include WithFriendlyId
  include WithIncomingEmail
  include Pundit::Authorization
  include ForInvestor
  include WithSupportAgent
  include InvestorShared
  include BlocksDestroyWithFundUnits
  # Lets an Investor have a WorkflowTemplate assigned/launched against it —
  # used for both LP onboarding and portfolio-company KPI report review.
  include Workflowable

  # Auto-assignment rules: access counters change constantly and are not routing data
  workflow_rule_fields except: %w[investor_access_count unapproved_investor_access_count]

  update_index('investor') { self if index_record? }

  # This is to be set if we want the investor name to be different from the investor_entity name
  attr_accessor :force_different_name

  # Any description of the investor
  has_rich_text :description

  belongs_to :investor_entity, class_name: "Entity"
  has_many :kpi_reports, through: :investor_entity
  # These are uploaded by the fund for its own portfolio_companies
  has_many :portfolio_kpi_reports, class_name: "KpiReport", foreign_key: :portfolio_company_id
  has_many :portfolio_kpis, class_name: "Kpi", through: :portfolio_kpi_reports, source: :kpis
  has_many :portfolio_report_extracts, dependent: :destroy, foreign_key: :portfolio_company_id

  belongs_to :entity, touch: true
  counter_culture :entity

  # The InvestorAccess attached to this investor
  has_many :investor_accesses, dependent: :destroy
  has_many :investor_advisors,
           through: :investor_entity,
           source: :investor_advisors

  has_many :investor_kpi_mappings, dependent: :destroy
  has_many :approved_investor_accesses, -> { where approved: true }, class_name: 'InvestorAccess'
  # The users linked to the InvestorAccess
  has_many :users, through: :investor_accesses
  has_many :approved_users, through: :approved_investor_accesses, source: :user

  # LP CRM MVP: options for the "Touch Point" dropdown on note/task forms —
  # every person recorded under this LP, approved (portal users) and unapproved
  # (CRM-only contacts) alike, as [display name, investor_access_id] pairs.
  # Notes/tasks link touch points via the InvestorAccess record so each
  # contact's history stays scoped to this stakeholder (see Note#touch_point).
  def touch_point_options
    investor_accesses.order(:first_name).map { |ia| ["#{ia.full_name} (#{ia.email})", ia.id] }
  end

  # The LP whose contacts may be used as touch points on notes/tasks owned by
  # this record — itself. DealInvestor answers with its parent LP's id, so both
  # owner types share one validation rule (see WithTouchPoint).
  def touch_point_investor_id
    id
  end
  has_many :rm_mappings, dependent: :destroy
  has_many :rm_mappings_as_rm, class_name: "RmMapping", foreign_key: :rm_id, dependent: :destroy
  has_many :mapped_investors_as_rm, through: :rm_mappings_as_rm, source: :investor

  has_many :tasks, as: :owner, dependent: :destroy
  has_many :valuations, as: :owner, dependent: :destroy

  # These are the access rights for the investor, to access items like Fund, InvestmentOpportunity, SecondarySale etc
  has_many :access_rights, foreign_key: :access_to_investor_id, dependent: :destroy
  # These are the access rights for employees, advisors etc, to access the details of this investor
  has_many :investor_access_rights, class_name: "AccessRight", as: :owner, dependent: :destroy

  has_many :deal_investors, dependent: :destroy
  has_many :deals, through: :deal_investors
  has_many :notes, as: :owner, dependent: :destroy
  has_many :aggregate_portfolio_investments, dependent: :destroy, foreign_key: :portfolio_company_id
  has_many :portfolio_investments, dependent: :destroy, foreign_key: :portfolio_company_id
  has_many :investment_instruments, dependent: :destroy, foreign_key: :portfolio_company_id
  has_many :portfolio_cashflows, dependent: :destroy, foreign_key: :portfolio_company_id
  has_many :stock_adjustments, dependent: :destroy, foreign_key: :portfolio_company_id

  has_many :investments, dependent: :destroy, foreign_key: :portfolio_company_id

  has_many :investor_kycs, dependent: :destroy
  has_many :capital_commitments, dependent: :destroy
  has_many :shareholder_positions, dependent: :destroy
  has_many :approval_responses, dependent: :destroy
  has_many :capital_distribution_payments, dependent: :destroy
  has_many :capital_remittances, dependent: :destroy
  has_many :fund_units, dependent: :destroy
  has_many :aml_reports, dependent: :destroy

  has_many :expression_of_interests, dependent: :destroy

  has_many :investor_notice_entries, dependent: :destroy

  has_many :offers, dependent: :destroy
  # has_many :messages, dependent: :destroy

  delegate :name, to: :entity, prefix: :investee
  validates :category, :investor_name, presence: true

  # Ensure investor_name is unique per entity_id
  validates :investor_name, uniqueness: { scope: :entity_id, message: "Please enter a unique stakeholder name, this name already exists in your stakeholder list" }
  validates :investor_name, length: { maximum: 255 }
  normalizes :investor_name, with: ->(investor_name) { investor_name.strip.squeeze(" ") }
  alias_attribute :name, :investor_name
  # Ensure unique investor_entity_id per entity_id
  validates :investor_entity_id, uniqueness: { scope: :entity_id, message: "Already exists as a Stakeholder." }

  validates :category, length: { maximum: 100 }
  validates :city, length: { maximum: 50 }
  validates :pan, length: { maximum: 40 }
  normalizes :pan, with: ->(pan) { pan.strip.squeeze(" ") }

  validates :primary_email, presence: true, if: proc { |e| e.new_record? }
  validates :primary_email, length: { maximum: 255 }
  validates_format_of :primary_email, with: URI::MailTo::EMAIL_REGEXP, multiline: true

  validates_uniqueness_of :primary_email, scope: :entity_id, message: "has already been used for a different stakeholder. Please enter a unique primary email ID."

  # Keeps the indexed domain column in step with primary_email. The mail add-ins match
  # senders by domain, and doing that as `primary_email LIKE '%@domain'` cannot use an
  # index — it scans every investor on each request. This column makes it an equality
  # lookup against idx_investors_on_email_domain_entity.
  # @see InvestorEmailMatcher
  before_save :sync_primary_email_domain, if: :will_save_change_to_primary_email?
  def sync_primary_email_domain
    self.primary_email_domain = primary_email.to_s.split("@").last.presence&.downcase
  end

  # The investor_entity_id duplicate is a side effect of the name/email match (see #update_name),
  # so it's redundant noise once either of those is already flagged.
  validate :suppress_redundant_entity_duplicate_error

  validates :tag_list, length: { maximum: 120 }

  validates :sector, length: { maximum: 255 }

  scope :with_tag_list, lambda { |tags|
    tags = tags.split(",").map(&:strip) unless tags.is_a?(Array)
    where(
      tags.map { "investors.tag_list LIKE ?" }.join(" OR "),
      *tags.map { |t| "%#{t}%" }
    )
  }

  # This is used to limit which employee can see which investors
  scope :for_employee, lambda { |user|
    joins(:investor_access_rights).where(investor_access_rights: { user_id: user.id })
  }

  scope :for, lambda { |user, startup_entity|
                where(entity_id: startup_entity.id,
                      investor_entity_id: user.entity_id)
              }

  scope :in_sector, lambda { |sector|
    next none if sector.blank?

    sectors = Array(sector).flat_map { |s| s.to_s.split(",") }.map(&:downcase).compact_blank
    next none if sectors.blank?

    where(sectors.map { "LOWER(sector) LIKE ?" }.join(" OR "), *sectors.map { |s| "%#{s}%" })
  }
  scope :for_vc, ->(vc_user) { where(investor_entity_id: vc_user.entity_id) }
  scope :not_interacted, ->(no_of_days) { where(last_interaction_date: ...(Time.zone.today - no_of_days.days)) }

  scope :with_access_rights, lambda { |entity_id, metadata|
    joins(entity: :access_rights).where(entity_id:).where("access_rights.access_to_category=investors.category or access_rights.access_to_investor_id=investors.id").where("access_rights.metadata=?", metadata)
  }

  # Get the investors associated with owner (Fund) which has access rights for investors
  scope :owner_access_rights, lambda { |owner, metadata|
    if metadata
      joins(entity: :access_rights).where(entity_id: owner.entity_id).where("access_rights.access_to_category=investors.category or access_rights.access_to_investor_id=investors.id").where("access_rights.metadata=?", metadata).where("owner_id=? and owner_type=?", owner.id, owner.class.name)
    else
      joins(entity: :access_rights).where(entity_id: owner.entity_id).where("access_rights.access_to_category=investors.category or access_rights.access_to_investor_id=investors.id").where("owner_id=? and owner_type=?", owner.id, owner.class.name)
    end
  }

  scope :perms, ->(p) { joins(:investor_entity).merge(Entity.perms(p)) }
  scope :no_perms, ->(p) { joins(:investor_entity).merge(Entity.no_perms(p)) }

  STANDARD_COLUMNS = { "Stakeholder; text-col" => "investor_name; text-col", "Tags; text-col" => "tag_list; text-col", "Category; text-col" => "category; text-col", "Access; label-col" => "investor_access_count; label-col", "City; text-col" => "city; text-col" }.freeze

  PC_AGENT_REPORT_COLUMNS = { "Stakeholder; text-col" => "investor_name; text-col", "Tags; text-col" => "tag_list; text-col", "Category; text-col" => "category; text-col", "Status; text-col" => "kpi_reporting_status; text-col" }.freeze

  INVESTOR_CATEGORIES = ENV["INVESTOR_CATEGORIES"].split(",") << "Prospective"

  def self.INVESTOR_CATEGORIES(entity = nil)
    cats = entity && entity.investor_categories.present? ? entity.investor_categories.split(",").map(&:strip) : INVESTOR_CATEGORIES
    cats += %w[Prospective]
    cats += ["Portfolio Company"] if ["Investment Fund", "Angel Fund"].include?(entity.entity_type) && entity
    cats
  end

  after_commit :change_investor_entity, if: :saved_change_to_investor_entity_id?

  after_create_commit -> { InvestorAddedJob.perform_later(id) unless imported }

  before_destroy :update_name_defunct
  def update_name_defunct
    update_column(:investor_name, "#{investor_name} Defunct #{rand(10_000)}")
  end

  before_validation :update_name, if: :new_record?

  def update_name
    self.last_interaction_date ||= Time.zone.today - 10.years

    # Ensure we have an investor entity (find by email, falling back to pan, else build new).
    # Shared with reassign_entity_on_email_change (update_investor.rb) so the two paths can't
    # drift on what counts as "the same" entity.
    e = if primary_email.present?
          with_entity_email_lock(primary_email.strip) { find_or_build_investor_entity }
        else
          find_or_build_investor_entity
        end

    errors.add(:investor_name, "is not valid. #{e.errors.full_messages}") unless e.valid?
    setup_permissions(e)
    e.save

    self.investor_entity = e

    self.investor_name = investor_entity.name if investor_name.blank?
    # self.pan ||= investor_entity.pan
  end

  before_validation :check_and_update_sector, if: -> { sector.present? }
  def check_and_update_sector
    # Sector is only relevant for Portfolio Companies, so if the category is changed to something else, we should clear the sector
    self.sector = "" if category != "Portfolio Company"
  end

  def suppress_redundant_entity_duplicate_error
    errors.delete(:investor_entity_id) if errors[:investor_name].any? || errors[:primary_email].any?
  end

  def setup_permissions(investor_entity)
    # We need to enable features if the entity creating the investor has them turned on
    # Ex. an Investment Fund creates and investor, who should have funds enabled
    investor_entity.permissions.set(:enable_documents) if entity.permissions.enable_documents?
    investor_entity.permissions.set(:enable_investments) if entity.permissions.enable_investments?
    investor_entity.permissions.set(:enable_secondary_sale) if entity.permissions.enable_secondary_sale?
    investor_entity.permissions.set(:enable_captable) if entity.permissions.enable_captable?

    investor_entity.permissions.set(:enable_funds) if entity.permissions.enable_funds?
    investor_entity.permissions.set(:enable_units) if entity.permissions.enable_units?
    investor_entity.permissions.set(:enable_kpis) if entity.permissions.enable_kpis?
    investor_entity.permissions.set(:enable_kycs) if entity.permissions.enable_kycs?
    investor_entity.permissions.set(:enable_approvals) if entity.permissions.enable_approvals?
    investor_entity.permissions.set(:enable_inv_opportunities) if entity.permissions.enable_inv_opportunities?
  end

  def emails(type = "Employees")
    case type
    when "Employees"
      investor_accesses.approved.not_investor_advisors.pluck(:email)
    when "Investor Advisors"
      investor_accesses.approved.investor_advisors.pluck(:email)
    when "All"
      investor_accesses.approved.pluck(:email)
    end
  end

  def emails_for(model)
    employee_emails = emails("Employees")
    advisor_emails = investor_advisor_emails(model)
    employee_emails + advisor_emails
  end

  def investor_advisor_emails(model)
    access_user_ids = get_access_rights(model).pluck(:user_id)
    investor_accesses.approved.investor_advisors.where(user_id: access_user_ids).pluck(:email)
  end

  def get_access_rights(model)
    model.access_rights.where.not(user_id: nil).where(entity_id: investor_entity_id)
  end

  def investor_advisors(model)
    access_user_ids = get_access_rights(model).pluck(:user_id)
    User.where(id: investor_accesses.approved.investor_advisors.where(user_id: access_user_ids).pluck(:user_id), whatsapp_enabled: true)
  end

  # Returns the aggregate portfolio investment for the given fund and as_of
  # Used in the FundFormulas to compute fund spcific AccountEntries
  def aggregate_portfolio_investment(fund_id: nil, as_of: nil)
    PortfolioCompanyCalc.new(self, fund_id:, as_of:).calculate
  end

  def folder_path
    "/Investors/#{investor_name.delete('/')}"
  end

  # Workflowable#workflow_display_name defaults to #to_s, but InvestorShared#to_s returns
  # "investor_name : category" — fine for admin lists, too noisy for workflow emails/instance
  # pages, so this overrides it to just investor_name.
  def workflow_display_name
    investor_name
  end

  # callback but only for category = Portfolio Company
  def valuation_updated(valuation)
    if valuation.synthetic
      Rails.logger.debug { "Not updating portfolio investments for synthetic valuation #{valuation.id}" }
    else
      # Ensure the portfolio_investments calculate the fmv
      pis = entity.portfolio_investments
                  .where(portfolio_company_id: id, investment_instrument: valuation.investment_instrument)
                  .includes(:fund, :investment_instrument, :aggregate_portfolio_investment, :documents, :form_type, :portfolio_company)
      pis.each do |pi|
        PortfolioInvestmentUpdate.call(portfolio_investment: pi, valuation: valuation)
      end
    end
  end

  def self.ransackable_associations(_auth_object = nil)
    [:support_agent_report].sort
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[city category investor_name tag_list investor_access_count unapproved_investor_access_count].sort
  end

  def update_investor_name(name)
    Rails.logger.debug { "Setting name for #{id} to #{name}" }
    update_column(:investor_name, name)
    reload
    CapitalCommitment.where(investor_id: id).update_all(investor_name:)
    CapitalRemittance.where(investor_id: id).update_all(investor_name:)
    CapitalDistributionPayment.where(investor_id: id).update_all(investor_name:)
    InvestorKyc.where(investor_id: id).update_all(investor_name:)
  end

  # Returns users who should receive a notification for this investor.
  #
  # model     – when present, restricts to users whose Pundit policy grants show?/overview? access.
  # with_tag: – subscription semantics: a contact with no tag_list is subscribed to ALL topics;
  #             a contact with tags is subscribed ONLY to topics whose tag is in their list.
  #             Contacts whose tag_list does not intersect with_tag are excluded.
  def notification_users(model = nil, with_tag: nil)
    accesses = approved_investor_accesses.includes(user: :roles)

    if with_tag.present?
      # Include access records that have no tag (subscribed to all) OR whose tag_list contains the topic.
      accesses = accesses.where(
        "investor_accesses.tag_list IS NULL OR investor_accesses.tag_list = '' " \
        "OR investor_accesses.tag_list LIKE ?",
        "%#{with_tag}%"
      )
    end

    # filter_map, not map: an InvestorAccess whose user row has been deleted yields nil, and one
    # nil takes down the entire notification rather than just that contact - Pundit.policy(nil,
    # model) below raises "Must be logged in" from ApplicationPolicy#initialize, so the caller
    # never gets a recipient list at all. A fund data room document whose access rights included a
    # single orphaned contact therefore notified NOBODY, healthy contacts included, with only an
    # exception to show for it. Callers that pass no model were equally exposed: a bare nil in the
    # returned array breaks anything doing pluck(:email) on it.
    #
    # Skipping the orphan notifies everyone else. Logged because the row is bad data that wants
    # cleaning up, and a silently skipped contact is how this stayed invisible in the first place.
    users = accesses.filter_map do |access|
      next access.user if access.user

      Rails.logger.warn(
        "InvestorAccess #{access.id} (#{access.email}) on investor #{id} has no usable login " \
        "(user_id: #{access.user_id.inspect}) - skipping this contact so the others are still notified"
      )
      nil
    end

    if model
      users.select do |user|
        policy = Pundit.policy(user, model)
        if user.has_cached_role?(:investor_advisor)
          # Use the original user object directly. dup clears the primary key and association cache,
          # causing has_cached_role? to fail. permissioned_investor_advisor? does not use curr_role.
          policy.permissioned_investor_advisor?(as_entity_id: investor_entity_id) ||
            policy.show? ||
            visible_from_home_entity?(user, model)
        else
          # For normal users, check show? first; fall back to overview? for models
          # (like Deal) where investors access via overview? rather than show?.
          policy.show? || (policy.respond_to?(:overview?) && policy.overview?)
        end
      end
    else
      users
    end
  end

  # An investor_advisor's entity_id is whichever host entity he last switched into — transient state
  # rewritten by InvestorAdvisor#switch/#revert, not a permission boundary. Judged by `policy.show?`
  # alone, a contact would receive or miss a notification depending on where he happened to be
  # switched when somebody else pressed Send ("No users to send the document" on a KYC document
  # whose only contact was an advisor switched into another client).
  #
  # Restricted to investor records in the advisor's OWN home entity — there he is the investor, not
  # acting as an advisor — and evaluated against User#home_persona, i.e. exactly the entity and
  # roles InvestorAdvisor.revert would leave him with. Roles borrowed from the host entity do not
  # carry over, so this can only confirm access he already holds at home, never add to it.
  def visible_from_home_entity?(user, model)
    return false unless investor_entity_id == user.advisor_entity_id

    persona = user.home_persona
    persona.present? && Pundit.policy(persona, model).show?
  end

  # The one definition of "someone at this investor will actually receive Capital Call emails"
  # for the given fund. Shared by the send-time grey-out (CapitalRemittance#notification_blocked_reasons),
  # the payment-confirmation gate, and the proactive checks at commitment-create and call-approve
  # time, so the four places can never drift apart. Note the semantics: a CC address on the
  # commitment does not count — only a named, approved contact does (see
  # docs/user_guides/capital_call_actions_and_notifications_matrix.md, Question 6).
  def capital_call_subscribers?(fund)
    notification_users(fund, with_tag: 'CapitalCall').any?
  end

  # add_to_user_access_rights_cache / remove_from_user_access_rights_cache removed:
  # AR grants are now read live from the DB; no per-investor cache propagation needed.

  def amount_invested
    amount = 0

    portfolio_investments.buys.each do |pi|
      Rails.logger.debug { "Calculating amount invested for #{pi.investment_instrument.name} on #{pi.investment_date} from #{pi.fund.currency} to #{entity.currency}" }

      bought_amount_cents = ExchangeRate.convert(pi.fund.currency, entity.currency, pi.amount_cents, pi.investment_date, entity_id, raise_missing_rate_error: true)
      amount += bought_amount_cents
    end

    Money.new(amount, entity.currency)
  end

  def portfolio_investment_ids
    @portfolio_investment_ids ||= portfolio_investments.pluck(:id)
    @portfolio_investment_ids
  end

  def get_row_template
    "/investors/investor"
  end

  def logo_doc
    documents.where(name: "Logo").first
  end

  # Units that must be deleted before this record can be (see BlocksDestroyWithFundUnits)
  def allocated_fund_units
    fund_units
  end

  def fund_units_block_label
    "stakeholder"
  end
end
