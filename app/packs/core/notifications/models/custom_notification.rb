class CustomNotification < ApplicationRecord
  include Trackable.new
  include WithFolder

  belongs_to :entity
  belongs_to :owner, polymorphic: true, touch: true

  scope :enabled, -> { where(enabled: true) }
  scope :not_enabled, -> { where(enabled: false) }
  scope :latest, -> { where(latest: true) }
  scope :not_latest, -> { where(latest: false) }
  scope :adhoc_notifications, -> { where(email_method: "adhoc_notification") }
  scope :for_type, ->(type) { where(for_type: type) }
  scope :email_method, ->(email_method) { where(email_method: email_method) }
  scope :with_tag, ->(tag) { where(tag: tag) }

  validates :subject, :body, presence: true
  validates :whatsapp, :subject, length: { maximum: 255 }
  validates :for_type, :email_method, length: { maximum: 100 }
  validates :tag, length: { maximum: 30 }, allow_blank: true

  # validates :email_method, uniqueness: { scope: %i[owner_id owner_type], message: ->(object, _data) { "#{object.email_method} already exists for #{object.owner}" } }
  after_create_commit :reset_latest
  def reset_latest
    # Update latest flag for all records with the same email_method, entity_id, owner_id, owner_type except the current record itself to false
    self.class.where(
      email_method: email_method,
      entity_id: entity_id,
      owner_id: owner_id,
      owner_type: owner_type
    ).where.not(id: id).update_all(latest: false)
  end
  # rubocop:enable Rails/SkipsModelValidations

  # We need to ensure that the whatsapp message does not have special characters, otherwise they are escaped by WA and look bad in the actual message
  validate :check_whatsapp
  SPECIAL = "&^#`~".freeze
  WA_REGEXP = /[#{SPECIAL.gsub(/./) { |char| "\\#{char}" }}]/
  def check_whatsapp
    # Check if the whatsapp message has special chars
    errors.add(:whatsapp, "can't have special characters") if WA_REGEXP.match?(whatsapp)
  end

  def to_s
    subject
  end

  FOR_TYPE_LABELS = {
    "CapitalCall" => "Call Notification",
    "CapitalDistribution" => "Distribution Notification",
    "Send Document" => "Document Notification",
    "InvestorKyc" => "KYC Notification",
    "InvestmentOpportunity" => "Investment Opportunity Notification"
  }.freeze

  # Drives the form's title - prefers for_type (what this notification is for) over owner_type
  # (who owns it), since a Fund can own a notification meant for its Calls or Distributions.
  def form_title
    label = FOR_TYPE_LABELS[for_type] || FOR_TYPE_LABELS[owner_type] || "Custom Notification"
    "#{label} : #{owner}"
  end

  FUND_FALLBACK_OWNER_TYPES = %w[CapitalCall CapitalDistribution].freeze

  # { email_method => subject } of the fund-level default(s) this owner would otherwise fall back
  # to, so the form can warn that saving here overrides the fund's default for that email.
  def fund_default_notifications
    return {} unless FUND_FALLBACK_OWNER_TYPES.include?(owner_type) && owner.respond_to?(:fund)

    email_methods.each_with_object({}) do |method, hash|
      default = owner.fund.custom_notification(method, for_type: owner_type)
      hash[method] = default.subject if default
    end
  end

  def show_link
    show_details_link
  end

  # Mailer class(es) that can handle this notification's for_type/owner_type. CapitalCall is the only
  # owner_type backed by two mailers (remittance vs payment), so this returns an array everywhere.
  def mailer_classes
    if for_type == "InvestorKyc"
      [InvestorKycMailer]
    elsif for_type == "Send Document"
      [DocumentMailer]
    elsif for_type == "InvestmentOpportunity"
      [InvestmentOpportunityMailer]
    elsif owner_type == "CapitalCall" || for_type == "CapitalCall"
      [CapitalRemittanceMailer, CapitalRemittancePaymentMailer]
    elsif owner_type == "CapitalDistribution" || for_type == "CapitalDistribution"
      [CapitalDistributionPaymentsMailer]
    elsif owner_type == "Fund"
      # FundInvestorKycMailer backs the "adhoc_kyc_notification" email_method (one email
      # per unique InvestorKyc, deduped across commitments that share one) — kept second
      # so mailer_class_for's fallback (mailer_classes.first) still resolves the
      # inherited-only "adhoc_notification" to CapitalCommitmentMailer.
      [CapitalCommitmentMailer, FundInvestorKycMailer]
    elsif owner_type == "Deal"
      [DealMailer]
    elsif owner
      ["#{owner.class.name}Mailer".safe_constantize].compact
    else
      []
    end
  end

  # rubocop:disable Lint/DuplicateBranch -- InvestorKyc/CapitalDistribution bodies coincide today but
  # for_type is checked ahead of owner_type intentionally, in case that ever diverges
  def email_methods
    mailer_methods = if for_type == "InvestorKyc"
                       mailer_classes.first.instance_methods(false).map(&:to_s)
                     elsif for_type == "Send Document"
                       %w[send_document]
                     elsif for_type == "InvestmentOpportunity"
                       InvestmentOpportunity::NOTIFICATION_METHODS
                     elsif owner_type == "CapitalCall" || for_type == "CapitalCall"
                       mailer_classes.flat_map { |klass| klass.instance_methods(false).map(&:to_s) }
                     elsif owner_type == "CapitalDistribution" || for_type == "CapitalDistribution"
                       mailer_classes.first.instance_methods(false).map(&:to_s)
                     elsif owner_type == "Fund"
                       # flat_map across both Fund mailers so FundInvestorKycMailer's own
                       # adhoc_kyc_notification method is discovered automatically.
                       # "adhoc_notification" is still appended manually because it's
                       # inherited-only on CapitalCommitmentMailer (never redefined there),
                       # so it never shows up via instance_methods(false).
                       mailer_classes.flat_map { |klass| klass.instance_methods(false).map(&:to_s) } + ["adhoc_notification"]
                     elsif owner_type == "Deal"
                       %w[adhoc_notification deal_activity_move]
                     elsif owner
                       mailer_classes.first&.instance_methods(false)&.map(&:to_s) || []

                     else
                       []
                     end
    # rubocop:enable Lint/DuplicateBranch

    mailer_methods.filter { |method| !method.start_with?("set_") }
  end

  # The mailer that actually owns a given email_method's PLACEHOLDERS. Falls back to the primary
  # (first) candidate for methods like "adhoc_notification" that are inherited from ApplicationMailer
  # rather than redefined on the subclass, so they don't show up in instance_methods(false).
  def mailer_class_for(method_name)
    mailer_classes.find { |klass| klass.instance_methods(false).map(&:to_s).include?(method_name.to_s) } || mailer_classes.first
  end

  def placeholders_for(method_name)
    klass = mailer_class_for(method_name)
    return [] unless klass

    klass::PLACEHOLDERS.keys.sort
  end

  # { email_method => [placeholder_name, ...] } for every email_method available to this notification.
  # Drives the "Insert placeholder" picker in the body editor - see _form.html.erb
  def placeholders_by_email_method
    email_methods.index_with { |method_name| placeholders_for(method_name) }
  end

  def render_erb_string
    renderer = ERB.new(body)
    # You need to set up the binding context. Here it’s done with the top-level binding, but it might be your controller or view context.
    renderer.result(binding)
  end

  PLACEHOLDER_REGEXP = /\{\{\s*(\w+)\s*\}\}/

  # Safe alternative to render_erb_string for clients who can't write ERB: substitutes {{name}}
  # tokens against the rendering mailer's PLACEHOLDERS allowlist. Never evaluates arbitrary code.
  # Unknown placeholders are left as-is so clients notice typos instead of getting silent blanks.
  def render_safe_body(mailer)
    placeholders = mailer.class::PLACEHOLDERS
    # rubocop:disable Rails/OutputSafety -- body is the client's own rich-text HTML (same as the
    # pre-existing non-erb path); only the substituted placeholder values are freshly html_escape'd above
    body.to_s.gsub(PLACEHOLDER_REGEXP) do |match|
      resolver = placeholders[Regexp.last_match(1)]
      value = resolver&.call(mailer)
      value.present? ? ERB::Util.html_escape(value.to_s) : match
    end.html_safe
    # rubocop:enable Rails/OutputSafety
  end

  def folder_path
    "#{owner.folder_path}/Notifications/#{id_or_random_int}"
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[created_at email_method enabled latest is_erb owner_id owner_type subject whatsapp tag for_type attachment_mandatory].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end
end
