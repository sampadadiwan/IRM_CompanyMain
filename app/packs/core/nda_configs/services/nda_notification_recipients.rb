# frozen_string_literal: true

# @description Resolves the correct recipients for each NDA notification event type.
#   Returns a hash with two keys: :gp_emails (Array of external email strings from
#   NdaConfig.notification_emails) and :lp_users (Array of User records from InvestorAccess
#   or NdaSignatory). The caller decides how to deliver to each — GP emails go directly
#   via NdaMailer.deliver_later, LP users go through Noticed notifiers.
#
# Changed: Module 8 — new service for NDA notification recipient resolution.
# Why: Recipient logic is complex (GP vs LP, signatories vs all users, exempt exclusion)
#   and shared between controller triggers and the daily expiry scanner. Extracting it
#   avoids duplication and keeps controllers thin.
#
# @see NdaEventNotifier — delivers to LP users via Noticed
# @see NdaReminderNotifier — delivers reminders to LP signatories via Noticed
# @see NdaMailer — GP emails sent directly
# @see NdaExpiryCheckJob — calls this service for expiry alert recipients
class NdaNotificationRecipients
  # @param event_type [Symbol] one of :accepted, :declined, :revoked, :new_version,
  #   :expiry_approaching, :expired, :reminder
  # @param nda_config [NdaConfig] the NDA configuration
  # @param investor [Investor, nil] the specific investor (nil for :reminder/:new_version
  #   which resolve investors internally)
  # @param options [Hash] optional overrides
  # @option options [Integer] :exclude_user_id user ID to exclude from LP recipients
  #   (e.g. the signer on acceptance confirmation)
  # @return [Hash{Symbol => Array}] { gp_emails: Array<String>, lp_users: Array<User> }
  def self.resolve(event_type, nda_config, investor = nil, options = {})
    new(nda_config).resolve(event_type, investor, options)
  end

  # @param nda_config [NdaConfig] the NDA configuration
  def initialize(nda_config)
    @nda_config = nda_config
  end

  # @param event_type [Symbol] the notification event type
  # @param investor [Investor, nil] the specific investor
  # @param options [Hash] optional overrides
  # @return [Hash{Symbol => Array}] { gp_emails: Array<String>, lp_users: Array<User> }
  def resolve(event_type, investor = nil, options = {})
    case event_type
    when :accepted
      { gp_emails: parsed_notification_emails, lp_users: [] }
    when :acceptance_confirm
      { gp_emails: [], lp_users: investor_users(investor, exclude_user_id: options[:exclude_user_id]) }
    when :declined # rubocop:disable Lint/DuplicateBranch -- same GP-only recipients as :accepted, kept separate for readability
      { gp_emails: parsed_notification_emails, lp_users: [] }
    when :revoked
      { gp_emails: [], lp_users: investor_users(investor) }
    when :new_version
      { gp_emails: [], lp_users: stale_acceptance_users }
    when :expiry_approaching, :expired
      { gp_emails: parsed_notification_emails, lp_users: signatory_users(investor) }
    when :reminder
      { gp_emails: [], lp_users: pending_signatory_users }
    else
      { gp_emails: [], lp_users: [] }
    end
  end

  private

  # @return [Array<String>] parsed email addresses from NdaConfig.notification_emails JSON.
  #   Returns empty array if blank or unparseable.
  def parsed_notification_emails
    return [] if @nda_config.notification_emails.blank?

    parsed = JSON.parse(@nda_config.notification_emails)
    parsed.is_a?(Array) ? parsed.select { |e| e.is_a?(String) && e.present? } : []
  rescue JSON::ParserError
    []
  end

  # @param investor [Investor] the investor whose users to return
  # @param exclude_user_id [Integer, nil] user ID to exclude (the signer)
  # @return [Array<User>] all InvestorAccess users of the investor for this entity,
  #   excluding exempt investors and optionally excluding a specific user
  def investor_users(investor, exclude_user_id: nil)
    return [] if investor.nil?
    return [] if investor_exempt?(investor)

    users = InvestorAccess
            .where(entity_id: @nda_config.entity_id, investor_id: investor.id, approved: true)
            .includes(:user)
            .filter_map(&:user)

    # Changed: Exclude the signer from acceptance confirmation.
    # Why: The signer already knows they accepted — no need to confirm to themselves.
    users = users.reject { |u| u.id == exclude_user_id } if exclude_user_id
    users
  end

  # @param investor [Investor] the investor whose signatories to return
  # @return [Array<User>] NDA signatory users of the investor for this NDA config.
  #   Returns empty if investor is exempt or has no signatories.
  def signatory_users(investor)
    return [] if investor.nil?
    return [] if investor_exempt?(investor)

    signatory_user_ids = NdaSignatory.where(nda_config_id: @nda_config.id).pluck(:user_id)
    return [] if signatory_user_ids.empty?

    # Changed: Intersect signatories with investor's InvestorAccess users.
    # Why: A signatory might belong to a different investor. Only return signatories
    #   that are also users of this specific investor for this entity.
    investor_user_ids = InvestorAccess
                        .where(entity_id: @nda_config.entity_id, investor_id: investor.id, approved: true)
                        .pluck(:user_id)

    matching_ids = signatory_user_ids & investor_user_ids
    User.where(id: matching_ids).to_a
  end

  # @return [Array<User>] LP users of all investors with stale acceptances (accepted
  #   an older NDA version). Used for version change notifications.
  def stale_acceptance_users
    stale_investor_ids = NdaAcceptance
                         .where(nda_config_id: @nda_config.id, status: "accepted")
                         .where.not(nda_version: @nda_config.version)
                         .distinct
                         .pluck(:investor_id)

    return [] if stale_investor_ids.empty?

    # Changed: Exclude exempt investors from version change notifications.
    # Why: Exempt investors bypass the NDA gate entirely — no need to notify them.
    exempt_investor_ids = InvestorAccess
                          .where(entity_id: @nda_config.entity_id, investor_id: stale_investor_ids, exempt_from_nda: true)
                          .distinct
                          .pluck(:investor_id)

    notifiable_investor_ids = stale_investor_ids - exempt_investor_ids
    return [] if notifiable_investor_ids.empty?

    InvestorAccess
      .where(entity_id: @nda_config.entity_id, investor_id: notifiable_investor_ids, approved: true)
      .includes(:user)
      .filter_map(&:user)
  end

  # @return [Array<User>] NDA signatory users of all Pending investors. Used for
  #   GP-triggered bulk reminders. Excludes exempt investors.
  def pending_signatory_users
    # Changed: Resolve pending investors by finding those without a valid acceptance.
    # Why: "Pending" is a derived status — no acceptance record or latest is declined/revoked.
    all_investor_ids = InvestorAccess
                       .where(entity_id: @nda_config.entity_id, approved: true)
                       .where(exempt_from_nda: [false, nil])
                       .distinct
                       .pluck(:investor_id)

    return [] if all_investor_ids.empty?

    # Changed: Find investors with a valid accepted acceptance (current version, not expired).
    # Why: Only investors without a valid acceptance are "Pending" for reminder purposes.
    accepted_investor_ids = NdaAcceptance
                            .where(nda_config_id: @nda_config.id, investor_id: all_investor_ids, status: "accepted")
                            .where(nda_version: @nda_config.version)
                            .distinct
                            .pluck(:investor_id)

    pending_investor_ids = all_investor_ids - accepted_investor_ids
    return [] if pending_investor_ids.empty?

    signatory_user_ids = NdaSignatory.where(nda_config_id: @nda_config.id).pluck(:user_id)
    return [] if signatory_user_ids.empty?

    # Changed: Intersect signatories with pending investors' users.
    # Why: Only send reminders to signatories who belong to a Pending investor.
    pending_user_ids = InvestorAccess
                       .where(entity_id: @nda_config.entity_id, investor_id: pending_investor_ids, approved: true)
                       .pluck(:user_id)

    matching_ids = signatory_user_ids & pending_user_ids
    User.where(id: matching_ids).to_a
  end

  # @param investor [Investor] the investor to check
  # @return [Boolean] true if any InvestorAccess for this investor is exempt from NDA
  def investor_exempt?(investor)
    InvestorAccess
      .exists?(entity_id: @nda_config.entity_id, investor_id: investor.id, exempt_from_nda: true)
  end
end
