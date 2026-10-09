class InvestorKyc < ApplicationRecord
  include Workflowable

  # Auto-assignment rules may also test the form type, and offer every KYC form's custom fields.
  # Left out: identifiers (routing mistakes, not routing data), and the amounts rolled up from
  # commitments and remittances — always 0 when a KYC is created, the only time a rule is checked
  # (workflow-rule-condition-builder card 1)
  workflow_rule_fields extra: %w[form_type_id],
                       except: %w[PAN bank_account_number ifsc_code address
                                  committed_amount call_amount collected_amount distribution_amount],
                       form_type_names: %w[IndividualKyc NonIndividualKyc InvestorKyc]

  # The KYC page shows a journey panel (investor-kyc-journey): open pages update live, and stalled
  # tasks remind the KYC's creator when that creator works for the fund (workflow_default_owner).
  has_journey

  STANDARD_COLUMNS = { "Investor; text-col" => "investor_name; text-col",
                       "Investing Entity; text-col" => "full_name; text-col",
                       "Type; text-col" => "kyc_type; text-col",
                       "Completed; text-col" => "completed_by_investor; text-col",
                       "Kyc Verified; text-col" => "verified; text-col",
                       "AML Status; text-col" => "aml_status; text-col",
                       "Expired; text-col" => "expired; text-col" }.freeze

  ONBOARDING_AGENT_REPORT_COLUMNS = {
    "Investor; text-col" => "investor_name; text-col",
    "Investing Entity; text-col" => "full_name; text-col",
    "Type; text-col" => "kyc_type; text-col",
    "Completed; text-col" => "completed_by_investor; text-col",
    "Kyc Verified; text-col" => "verified; text-col",
    "AML Status; text-col" => "aml_status; text-col",
    "Expired; text-col" => "expired; text-col",
    "Status; text-col" => "onboarding_status; text-col"
  }.freeze

  INVESTOR_TAB_STANDARD_COLUMNS = STANDARD_COLUMNS.except("Investor; text-col").freeze

  INVESTOR_STANDARD_COLUMNS = { "Entity; text-col" => "entity_name; text-col",
                                "Investing Entity; text-col" => "full_name; text-col",
                                "Type; text-col" => "kyc_type; text-col",
                                "Completed; text-col" => "completed_by_investor; text-col",
                                "Kyc Verified; text-col" => "verified; text-col",
                                "AML Status; text-col" => "aml_status; text-col",
                                "Expired; text-col" => "expired; text-col" }.freeze

  AML_STATUSES = %w[no_match potential_match].freeze

  SEBI_INVESTOR_CATEGORIES = %i[Internal Domestic Foreign Other].freeze

  SEBI_INVESTOR_SUB_CATEGORIES_MAPPING = {
    Internal: ["Sponsor", "Manager", "Directors/Partners/Employees of Sponsor", "Directors/Partners/Employees of Manager", "Employee Benefit Trust of Manager"],
    Domestic: ["Banks", "NBFCs", "Insurance Companies", "Pension Funds", "Provident Funds", "AIFs", "Other Corporates", "Resident Individuals", "Non-Corporate (other than Trusts)", "Trusts"],
    Foreign: ["FPIs", "FVCIs", "NRIs", "Foreign Others"],
    Other: ["Domestic Developmental Agencies/Government Agencies", "Others"]
  }.freeze
  # Reporting fields as per regulatory environment
  REPORTING_FIELDS = {
    sebi: {
      sebi_investor_category: { field_type: "Select",
                                meta_data: ",#{SEBI_INVESTOR_CATEGORIES.join(',')}",
                                label: "Investor Category",
                                js_events: "change->form-custom-fields#investor_category_changed" },
      sebi_investor_sub_category: { field_type: "Select",
                                    meta_data: SEBI_INVESTOR_SUB_CATEGORIES_MAPPING.values.flatten.join(","),
                                    label: "Investor Sub Category" }
    }
  }.freeze

  # Make all models searchable
  update_index('investor_kyc') { self if index_record?(InvestorKycIndex) }
  include WithCustomField
  include Trackable.new
  include WithFolder
  include ForInvestor
  include RansackerAmounts.new(fields: %w[collected_amount committed_amount call_amount distribution_amount])
  include WithFriendlyId
  include WithIncomingEmail
  include InvestorKycConcern
  include WithSupportAgent

  belongs_to :investor
  belongs_to :entity
  # These are the capital_commitments that are linked to this KYC
  has_many :capital_commitments

  has_many :funds, through: :capital_commitments
  has_many :capital_remittances, through: :capital_commitments
  has_many :capital_remittance_payments, through: :capital_commitments
  has_many :capital_distribution_payments, through: :capital_commitments
  has_many :account_entries, through: :capital_commitments
  has_many :fund_units, through: :capital_commitments

  # These are the expression_of_interests that are linked to this KYC
  has_many :expression_of_interests

  has_many :noticed_events, as: :record, dependent: :destroy, class_name: "Noticed::Event"

  has_many :aml_reports, dependent: :destroy
  has_many :kyc_datas, dependent: :destroy
  # Document Checks runs of this KYC (results go with them)
  has_many :doc_check_runs, as: :record, dependent: :destroy

  scope :uncalled, -> { where('committed_amount_cents > call_amount_cents') }
  scope :due, -> { where('committed_amount_cents > collected_amount_cents') }
  scope :agreement_uncalled, -> { where('agreement_committed_amount_cents > call_amount_cents') }
  scope :agreement_overcalled, -> { where('agreement_committed_amount_cents <= call_amount_cents') }

  scope :verified, -> { where(verified: true) }
  scope :completed, -> { where(completed_by_investor: true) }
  scope :not_completed, -> { where(completed_by_investor: false) }
  scope :unverified, -> { where(verified: false) }
  scope :pending_investor, -> { where(submission_status: %w[link_sent draft_saved]) }
  # Exclusive end (...) — a KYC is valid THROUGH its expiry date, matching both
  # #expired? (expiry_date < today) and :not_expired (expiry_date >= today).
  # The old inclusive form counted a KYC expiring today as already expired.
  scope :expired, -> { where(expiry_date: ...Time.zone.today) }
  scope :not_expired, -> { where('expiry_date IS NULL OR expiry_date >= ?', Time.zone.today) }

  scope :for_investor, lambda { |user|
    joins(:investor).where('investors.investor_entity_id': user.entity_id).joins(entity: :investor_accesses).merge(InvestorAccess.approved_for_user(user))
  }

  # Do not call this with a user who is not an investor_advisor
  scope :for_investor_advisor, lambda { |user, across_all_entities: false|
    # We cant show them all the KYCs, only the ones for the funds they have been permissioned
    fund_ids = Fund.for_investor(user, across_all_entities:).distinct.pluck(:id)

    if across_all_entities && user.has_cached_role?(:investor_advisor)
      joins(investor: :investor_accesses, capital_commitments: :fund)
        .where(funds: { id: fund_ids })
        .merge(InvestorAccess.approved_for_user(user, across_all_entities:)).distinct
    else
      # Give access to all the KYCs for the investor, where he has investor_accesses approved
      # And the investor belongs to the same investor_entity as the user
      # and the fund is one of the funds they have been permissioned
      joins(:investor, capital_commitments: :fund)
        .where('investors.investor_entity_id=? and funds.id in (?)', user.entity_id, fund_ids)
        .joins(entity: :investor_accesses).merge(InvestorAccess.approved_for_user(user)).distinct
    end
  }

  enum :kyc_type, { individual: "Individual", non_individual: "Non Individual" }

  attribute :submission_status, :string, default: "not_sent"
  enum :submission_status, {
    not_sent: "not_sent",
    link_sent: "link_sent",
    draft_saved: "draft_saved",
    completed: "completed",
    verified: "verified"
  }, prefix: :submission

  include FileUploader::Attachment(:signature)

  attr_accessor :phone

  belongs_to :verified_by, class_name: "User", optional: true

  validates :kyc_type, :address, :full_name, :birth_date, :PAN, :bank_name, :bank_branch, :bank_account_type, :bank_account_number, :ifsc_code, presence: true

  validates :PAN, length: { maximum: 15 }
  validates :bank_account_number, :bank_account_type, length: { maximum: 40 }
  validates :ifsc_code, :agreement_unit_type, length: { maximum: 20 }
  validates :full_name, length: { maximum: 255 }
  normalizes :full_name, with: ->(full_name) { full_name.strip.squeeze(" ") }
  validates :kyc_type, length: { maximum: 15 }
  validates :bank_name, length: { maximum: 100 }
  validates :bank_branch, length: { maximum: 255 }
  validates :bank_account_type, length: { maximum: 40 }
  validates :phone, length: { is: 10 }, allow_blank: true

  # remove spaces in esign_emails
  normalizes :esign_emails, with: ->(v) { v&.gsub(/\s+/, '') }
  validate :esign_emails_must_be_valid, if: -> { esign_emails.present? }

  validate :birth_date_cannot_be_in_the_future
  def birth_date_cannot_be_in_the_future
    errors.add(:birth_date, "can't be in the future") if birth_date.present? && birth_date > Date.current
  end

  validate :check_required_file_type_custom_fields, if: -> { skip_cf_before_save != true }
  validate :sebi_investor_sub_category_hierarchy

  # Called by valid? (e.g. inside handle_errors) to surface required File custom-field errors even when
  # save(validate:false) was originally used. form_type may be nil on new records because setup_form_type
  # is a before_save callback, so we resolve the form type via type_from_kyc_type ourselves.
  def check_required_file_type_custom_fields
    type_name = respond_to?(:type_from_kyc_type) ? (type_from_kyc_type || self.class.name) : self.class.name
    ft = form_type || entity&.form_types&.where(name: type_name)&.last
    return if ft.blank?

    ft.form_custom_fields.where(field_type: "File", required: true).find_each do |fcf|
      document_name = fcf.label.presence || fcf.name.humanize
      next if documents.any? { |d| d.name == document_name }

      errors.add(:base, "#{document_name} can't be blank")
    end
  end

  def sebi_investor_sub_category_hierarchy
    json_fields["sebi_investor_category"] = json_fields["sebi_investor_category"]&.strip&.titleize
    json_fields["sebi_investor_sub_category"] = json_fields["sebi_investor_sub_category"]&.strip

    # Rule: category must exist if sub-category exists
    if json_fields["sebi_investor_sub_category"].present? && json_fields["sebi_investor_category"].blank?
      errors.add(:sebi_investor_category, "should be present to enter investor sub-category")
      return
    end

    # If category exists, validate it
    if json_fields["sebi_investor_category"].present?
      allowed_categories = SEBI_INVESTOR_CATEGORIES.map(&:to_s)
      unless allowed_categories.include?(json_fields["sebi_investor_category"])
        errors.add(:sebi_investor_category, "should be one of #{allowed_categories.join(', ')}")
        return
      end

      # Validate sub-category if present
      if json_fields["sebi_investor_sub_category"].present?
        allowed_sub_categories = SEBI_INVESTOR_SUB_CATEGORIES_MAPPING[json_fields["sebi_investor_category"].to_sym] || []
        errors.add(:sebi_investor_sub_category, "should be one of #{allowed_sub_categories.join(', ')}") unless allowed_sub_categories.include?(json_fields["sebi_investor_sub_category"])
      end
    end
  end

  # Customize form
  serialize :pan_verification_response, type: Hash
  serialize :bank_verification_response, type: Hash

  # Note this rollups work only where Fund and Entity currency are the same.
  monetize :committed_amount_cents, :collected_amount_cents, :agreement_committed_amount_cents,
           :call_amount_cents, :distribution_amount_cents, :uncalled_amount_cents, :other_fee_cents,
           with_currency: ->(i) { i.entity.currency }

  # Should be called only from SendKycFormJob
  # If not this leads to bugs where the InvestorKycNotification cannot be created when the kyc_type changes
  def send_kyc_form(reminder: false, custom_notification_id: nil)
    if send_kyc_form_to_user || reminder
      update_columns(submission_status: "link_sent", link_sent_at: Time.current) unless submission_completed? || submission_verified?
      # rubocop:enable Rails/SkipsModelValidations
      email_method = :notify_kyc_required
      msg = "Kindly update your KYC details for #{entity.name} by clicking on the button below"

      if reminder
        email_method = :kyc_required_reminder
        msg = "Reminder to kindly update your KYC details for #{entity.name} by clicking on the button below."
      end

      # Send notification to all the users who have access to this KYC
      notification_users.each do |user|
        InvestorKycNotifier.with(record: self, entity_id:, email_method:, msg:, user_id: user.id, custom_notification_id:).deliver_later(user)
      end

      # Ensure the flag is set to false after sending the KYC form
      # rubocop:disable Rails/SkipsModelValidations
      if reminder
        update_columns(reminder_sent: true, reminder_sent_date: Time.zone.now, send_kyc_form_to_user: false)
      else
        update_column(:send_kyc_form_to_user, false)
      end
      # rubocop:enable Rails/SkipsModelValidations

      # update_columns skips callbacks, so tell the journey ("Send KYC form" is done) explicitly
      # Worked examples H3 — openspec/changes/investor-kyc-journey/design.md#worked-examples
      journey_progress!
    end
  end

  def notification_users
    investor.notification_users(with_tag: 'KYC').select do |user|
      # Check if the user has access to this KYC
      # For investor advisors, check if they have access to the kyc across all the entities they are advisors for
      across_all_entities = user.has_cached_role?(:investor_advisor)
      Rails.logger.debug { "Checking user: #{user.id} for KYC: #{id} across_all_entities: #{across_all_entities}" }
      policy = InvestorKycPolicy.new(user, self)
      policy.show?(across_all_entities:) ||
        # across_all_entities only sees user-level access rights, so an advisor who is a plain
        # contact on his OWN record was never matched. Plain show? is what the UI authorizes for
        # his current persona (for a non-advisor it is the same call, so skip it); the home-entity
        # check covers him while switched into a client (same rule as Investor#notification_users).
        # Neither exceeds what he can open.
        (across_all_entities && policy.show?) ||
        investor.visible_from_home_entity?(user, self)
    end
  end

  def pan_card
    documents.where(owner_tag: "PAN").last&.file
  end

  def updated_notification(msg: nil)
    NotifyKycJob.perform_later(id, email_method: "notify_kyc_updated", msg: msg || "KYC updated for #{full_name}")
  end

  def updates_requested_notification(msg: nil)
    NotifyKycJob.perform_later(id, email_method: "notify_updates_requested", msg: msg || "Updates requested for KYC: #{full_name}")
  end

  # The investor's final submit, as distinct from updated_notification's "they changed something".
  # Routed through notify_kyc like the other two so all three share one recipient rule - this used
  # to be sent straight from InvestorKycsController with a recipient list of its own, which meant a
  # final submit fired both it and updated_notification, and investor advisors got only the latter.
  # The email itself ignores msg: (notify_kyc_submitted.html.erb always renders its own formatted
  # body); it is still passed so the in-app notification - which shares InvestorKycNotifier#message
  # with the email - has a non-blank body of its own.
  def submitted_notification(msg: nil)
    NotifyKycJob.perform_later(id, email_method: "notify_kyc_submitted", msg: msg || "KYC submitted by investor: #{full_name}")
  end

  # Shared by updated_notification, updates_requested_notification and submitted_notification (via
  # NotifyKycJob, which runs this off the request thread): notifies the entity's own employees and
  # any investor advisors holding a grant on the entity. Each recipient must pass
  # InvestorKycPolicy#show? - the same rule as the KYC list and page - so nobody is emailed a link
  # they will get "access denied" on. A KYC with no commitment yet is emailed only to those who can
  # see it - company admins and employees with Investor Kyc Read / Update (V5); there is no
  # separate onboarding fallback for other employees.
  # Worked examples V1-V11: openspec/changes/kyc-advisor-notification-delivery-fix/design.md#worked-examples
  # Deduplicated by user id across both loops, since a legacy advisor account with a nil
  # advisor_entity_id can appear in both.
  def notify_kyc(msg:, email_method:)
    notified_user_ids = Set.new

    entity.employees.not_investor_advisor_roles.active.each do |user|
      # enable_kycs is checked here as well as inside show? because show? lets a company admin
      # open any KYC without it, while the KYC emails need it for everyone (V6).
      if user.enable_kycs && InvestorKycPolicy.new(user, self).show?
        InvestorKycNotifier.with(record: self, entity_id:, email_method:, msg:, user_id: user.id).deliver_later(user)
        notified_user_ids << user.id
      else
        Rails.logger.debug { "Not sending KYC notification (#{email_method}) to user #{user.id} as they do not have enable_kycs permission or show access" }
      end
    end

    entity.investor_advisors.includes(:user).find_each do |investor_advisor|
      user = investor_advisor.user
      # A grant can outlive its user row, so skip rather than abort the job and lose every
      # remaining advisor's notification.
      next if user.nil? || notified_user_ids.include?(user.id)
      next unless user.active

      # The grant's enable_kycs, not user.enable_kycs: the latter reads whichever entity the
      # advisor is switched into right now, so a switched-out advisor would be emailed or not
      # depending on an unrelated entity's settings (V7, V9).
      next unless investor_advisor.permissions.enable_kycs? && entity.permissions.enable_kycs?
      next unless InvestorKycPolicy.new(user, self).show?

      InvestorKycNotifier.with(record: self, entity_id:, email_method:, msg:, user_id: user.id).deliver_later(user)
    end
  end

  after_save :sync_boolean_fields_from_status
  # Keeps completed_by_investor and verified booleans in sync with submission_status
  # so all existing scopes and code continue to work without change.
  def sync_boolean_fields_from_status
    expected_completed = submission_completed? || submission_verified?
    expected_verified  = submission_verified?
    updates = {}
    updates[:completed_by_investor] = expected_completed if completed_by_investor != expected_completed
    updates[:verified] = expected_verified if verified != expected_verified
    # rubocop:disable Rails/SkipsModelValidations
    update_columns(updates) if updates.any?
    # rubocop:enable Rails/SkipsModelValidations
  end

  before_save :set_investor_name
  def set_investor_name
    self.type = type_from_kyc_type
    Rails.logger.debug { "self.type: #{type}" }
    self.investor_name = investor.investor_name
  end

  def due_amount
    call_amount - collected_amount + other_fee
  end

  def uncalled_amount
    custom_committed_amount - call_amount
  end

  def type_from_kyc_type
    "#{kyc_type.titleize.delete(' ')}Kyc" if kyc_type.present?
  end

  def custom_committed_amount
    agreement_committed_amount_cents.positive? ? agreement_committed_amount : committed_amount
  end

  def folder_path
    base = investor&.folder_path || "KYC"
    label = full_name.presence || investor&.investor_name || "Unknown"
    "#{base}/KYC-#{id_or_random_int}/#{label.delete('/')}"
  end

  def investor_signatories
    esign_emails&.split(",")&.map(&:strip)
  end

  def to_s
    full_name || investor_name
  end

  # workflow_display_name uses Workflowable default (to_s → full_name || investor_name).
  # workflow_url uses Workflowable default (investor_kyc_path).
  # Override workflow_attachable_files: documents are polymorphically linked, not a direct association.
  def workflow_attachable_files
    Document.where(owner: self).to_a
  end

  # Who is reminded about a stalled journey task when the step names no owner: the creator, but only
  # when they work for the fund — an investor who created their own KYC must never get reminders
  # about the fund's tasks (design Decision 10).
  # Worked examples E23 — openspec/changes/investor-kyc-journey/design.md#worked-examples
  def workflow_default_owner
    creator = super
    creator if creator && creator.entity_id == entity_id
  end

  def enable_kyc
    investor.investor_entity.permissions.set(:enable_kycs)
    investor.investor_entity.save
  end

  def generate_aml_report(user_id)
    GenerateAmlReportJob.perform_later(id, user_id) if id.present? && full_name.present?
  end

  # Lets a fund manually correct an AML status set by the automated IDFy check (e.g. a false
  # positive from a name match). Once overridden, AmlReportAsyncDownloadJob stops auto-writing
  # aml_status so a later IDFy run can't silently revert the decision.
  def override_aml_status!(status:, reason:)
    self.audit_comment = reason
    assign_attributes(aml_status: status, aml_manual_override: true, aml_override_reason: reason)
    save(validate: false)
  end

  def full_name_has_changed?
    full_name.present? && saved_change_to_full_name?
  end

  def expired?
    expiry_date ? expiry_date < Time.zone.today : false
  end

  def assign_kyc_data(kyc_data, user)
    self.full_name = kyc_data.full_name
    self.address = kyc_data.perm_address
    self.corr_address = kyc_data.corr_address
    # add below images as attached documents
    kyc_data.get_image_data.each do |image_data|
      imgtype = image_data['image_type']
      file_name = "#{kyc_data.source.upcase}Data-#{id}-#{full_name.delete('/')}-#{imgtype}.png"
      file_path = "tmp/#{file_name}"
      if imgtype.casecmp?("pan")
        Rails.logger.debug { "Uploading new image - #{file_name}" }
        Rails.root.join(file_path).binwrite(Base64.decode64(image_data['data']))
        Document.create!(name: "Upload Pan Card", entity_id:, owner: self, user:, file: File.open(file_path, "rb"))
      end

      FileUtils.rm_f(file_path)
    rescue StandardError => e # caught as kyc can have improper base64 data
      Rails.logger.error { "Error while uploading file #{file_name} #{e.message}" }
    end
  end

  def remove_images
    # remove attached image documents from kyc data
  end

  def commitment_pending
    committed_amount - collected_amount
  end

  def total_fund_units
    # Find all the committments this kyc is tied to
    entity.fund_units.joins(capital_commitment: :investor_kyc).where("investor_kycs.id=?", id).sum(:quantity)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[PAN full_name investor_name kyc_type address bank_name bank_branch bank_account_type bank_account_number ifsc_code birth_date verified completed_by_investor expiry_date collected_amount committed_amount call_amount distribution_amount docs_completed created_at aml_status submission_status].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[capital_commitments investor funds support_agent_report]
  end

  def self.ransackable_scopes(_auth_object = nil)
    %i[verified expired not_expired due]
  end

  def face_value_for_redemption(start_date: nil, end_date: nil)
    cdp = capital_distribution_payments
    cdp = cdp.where(payment_date: start_date..) if start_date.present?
    cdp = cdp.where(payment_date: ..end_date) if end_date.present?
    Money.new(cdp.sum(:cost_of_investment_cents), entity.currency)
  end

  def self.cleanup_zeros(ent)
    ent.investor_kycs.each do |kyc|
      kyc.properties.each do |name, val|
        kyc.properties.delete(name) if val == "0"
      end
      kyc.save(validate: false)
    end
    nil
  end

  # In some cases the agreement_unit_type is specified in the KYC, before a commitment is created.
  # And we need the corresponding fund unit setting (for document generation), from any fund in the entity. This is for Angel Funds only. For other funds, the agreement_unit_type is not used.
  def agreement_unit_setting
    entity.funds.first.fund_unit_settings.where(name: agreement_unit_type).first
  end

  def ckyc_data
    kyc_datas.ckyc.where(PAN: self.PAN).last
  end

  def kra_data
    kyc_datas.kra.where(PAN: self.PAN).last
  end

  def kyc_data_fields_populated
    full_name.present? || address.present? || corr_address.present?
  end

  def pan=(value)
    self.PAN = value.strip if value.present?
  end

  def pan
    self.PAN
  end
end
