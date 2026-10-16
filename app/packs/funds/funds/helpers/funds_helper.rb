module FundsHelper
  def fund_bread_crumbs(current = nil)
    @bread_crumbs = { Funds: funds_path }
    @bread_crumbs[Fund.find(params[:fund_id]).name] = fund_path(params[:fund_id]) if params[:fund_id].present?
    @bread_crumbs[current] = nil if current
  end

  def investor_commitments_chart(capital_commitments)
    commitments = capital_commitments.joins(:fund, :investor)
                                     .order(commitment_date: :asc)
                                     .group_by { |v| v.fund.name }
                                     .map do |fname, vals|
      [fname,
       vals.inject(0) { |sum, com| sum + com.committed_amount.to_f },
       vals.inject(0) { |sum, com| sum + com.call_amount.to_f },
       vals.inject(0) { |sum, com| sum + com.collected_amount.to_f },
       vals.inject(0) { |sum, com| sum + com.distribution_amount.to_f }]
    end

    # column_chart cumulative(commitments), library: {
    #   plotOptions: { column: {
    #     dataLabels: {
    #       enabled: true,
    #       format: "{point.y:,.2f}"
    #     }
    #   } }
    # }

    column_chart [
      { name: "Committed", data: commitments.map { |k| [k[0], k[1]] } },
      { name: "Called", data: commitments.map { |k| [k[0], k[2]] } },
      { name: "Collected", data: commitments.map { |k| [k[0], k[3]] } },
      { name: "Distributed", data: commitments.map { |k| [k[0], k[4]] } }
    ],
                 library: {
                   plotOptions: { column: {
                     dataLabels: {
                       enabled: true,
                       format: "{point.y:,.2f}"
                     }
                   } },
                   **chart_theme_color
                 }
  end

  # Maps each model class that has a dedicated notification topic to its canonical tag name.
  # Contacts whose tag_list intersects this tag (or have no tag) receive the notification.
  NOTIFICATION_TAG_FOR_MODEL = {
    "CapitalCall" => "CapitalCall",
    "CapitalDistribution" => "Distribution",
    "CapitalDistributionPayment" => "CapitalCall"
  }.freeze

  # Provides a comprehensive list of email-related statistics and investor access details
  # for a given model (Fund, CapitalCall, or CapitalDistribution).
  #
  # @param model [Object] An instance of Fund, CapitalCall, CapitalDistribution, or CapitalDistributionPayment.
  # @return [Hash] A hash containing various counts and collections related to folios,
  #   investors, and user access rights for email communication.
  def email_list_for(model)
    # Initialize core data based on the model type
    data = initialize_email_list_data(model)
    capital_commitments = data[:capital_commitments]
    access_rights = data[:access_rights]
    investors = data[:investors]
    investor_accesses = data[:investor_accesses]

    # Derive the notification topic tag for this model so we can reflect subscription filtering.
    tag = NOTIFICATION_TAG_FOR_MODEL[model.class.name]

    # Calculate statistics related to folios (capital commitments)
    folio_stats = calculate_folio_stats(capital_commitments, access_rights, investors)

    # Calculate statistics related to investors
    investor_stats = calculate_investor_stats(investors)

    # Calculate statistics and filter investor accesses related to user email permissions
    user_access_stats = calculate_user_access_stats(model, investor_accesses, tag:)

    # Combine all calculated statistics into a single hash for return
    {
      notification_tag: tag,
      no_of_folios: folio_stats[:no_of_folios],
      no_of_folios_no_email: folio_stats[:no_of_folios_no_email],
      no_of_folios_with_email: folio_stats[:no_of_folios_with_email],
      no_of_investors: investor_stats[:no_of_investors],
      no_of_investors_no_email: investor_stats[:no_of_investors_no_email],
      no_of_investors_with_email: investor_stats[:no_of_investors_with_email],
      no_of_users: user_access_stats[:no_of_users],
      no_of_users_no_email: user_access_stats[:no_of_users_no_email],
      no_of_users_with_email: user_access_stats[:no_of_users_with_email],
      commitments_wo_access_rights: folio_stats[:commitments_wo_access_rights],
      commitment_wo_investor_accesses: folio_stats[:commitment_wo_investor_accesses],
      unapproved_investor_accesses: user_access_stats[:unapproved_investor_accesses],
      approved_investor_access: user_access_stats[:approved_investor_access],
      approved_investor_access_count: user_access_stats[:approved_investor_access_count],
      approved_investor_access_ia: user_access_stats[:approved_investor_access_ia],
      approved_investor_access_ia_count: user_access_stats[:approved_investor_access_ia_count],
      email_disabled_investor_accesses: user_access_stats[:email_disabled_investor_accesses],
      tag_excluded_investor_accesses: user_access_stats[:tag_excluded_investor_accesses]
    }
  end

  private

  # Initializes and returns the core data (capital commitments, access rights, investors, investor accesses)
  # based on the type of the provided model.
  #
  # @param model [Object] An instance of Fund, CapitalCall, or CapitalDistribution.
  # @return [Hash] A hash containing initialized ActiveRecord relations.
  def initialize_email_list_data(model)
    case model.class.name
    when "Fund"
      capital_commitments = model.capital_commitments
      access_rights = model.access_rights
      investors = model.committed_investors
      investor_accesses = model.entity.investor_accesses.joins(:investor).merge(investors).distinct
    when "CapitalCall"
      # For CapitalCall, fund-related data is accessed via model.fund
      capital_commitments = model.capital_commitments
      access_rights = model.fund.access_rights
      investors = model.committed_investors
      investor_accesses = model.entity.investor_accesses.joins(:investor).merge(investors).distinct
    when "CapitalDistribution"
      # For CapitalDistribution, fund-related data is accessed via model.fund
      capital_commitments = model.capital_commitments
      access_rights = model.fund.access_rights
      investors = model.investors
      investor_accesses = model.entity.investor_accesses.joins(:investor).merge(investors).distinct
    when "CapitalDistributionPayment"
      # For CapitalDistributionPayment, fund-related data is accessed via model.capital_distribution.fund
      capital_commitments = model.fund.capital_commitments.where(id: model.capital_commitment_id)
      access_rights = model.fund.access_rights.where(access_to_investor_id: model.investor_id)
      investors = model.entity.investors.where(id: model.investor_id)
      investor_accesses = model.entity.investor_accesses.where(investor_id: model.investor_id)
    else
      # Handle unexpected model types or raise an error
      raise ArgumentError, "Unsupported model type: #{model.class.name}"
    end
    {
      capital_commitments: capital_commitments,
      access_rights: access_rights,
      investors: investors,
      investor_accesses: investor_accesses
    }
  end

  # Calculates statistics related to capital commitments (folios).
  #
  # @param capital_commitments [ActiveRecord::Relation] Collection of capital commitments.
  # @param access_rights [ActiveRecord::Relation] Collection of access rights.
  # @param investors [ActiveRecord::Relation] Collection of investors.
  # @return [Hash] A hash containing folio counts and specific commitment collections.
  def calculate_folio_stats(capital_commitments, access_rights, investors)
    # Commitments that do not have access rights for the investor in this fund
    commitments_wo_access_rights = capital_commitments.where.not(investor_id: access_rights.pluck(:access_to_investor_id)).includes(:investor).distinct
    # Commitments that do not have investor access for the investor in this fund
    commitment_wo_investor_accesses = capital_commitments.where(investor_id: investors.without_investor_accesses.select(:id)).includes(:investor).distinct

    # Total number of folios (capital commitments)
    no_of_folios = capital_commitments.count
    # Number of folios that do NOT have email access (union of commitments without access rights and without investor access)
    no_of_folios_no_email = (commitments_wo_access_rights.pluck(:id) | commitment_wo_investor_accesses.pluck(:id)).length
    # Number of folios that DO have email access
    no_of_folios_with_email = no_of_folios - no_of_folios_no_email

    {
      no_of_folios: no_of_folios,
      no_of_folios_no_email: no_of_folios_no_email,
      no_of_folios_with_email: no_of_folios_with_email,
      commitments_wo_access_rights: commitments_wo_access_rights,
      commitment_wo_investor_accesses: commitment_wo_investor_accesses
    }
  end

  # Calculates statistics related to investors.
  #
  # @param investors [ActiveRecord::Relation] Collection of investors.
  # @return [Hash] A hash containing investor counts.
  def calculate_investor_stats(investors)
    # Total number of investors
    no_of_investors = investors.count
    # Number of investors who will NOT receive emails (based on will_receive_email flag)
    no_of_investors_no_email = investors.where(will_receive_email: 0).count
    # Number of investors who WILL receive emails
    no_of_investors_with_email = no_of_investors - no_of_investors_no_email

    {
      no_of_investors: no_of_investors,
      no_of_investors_no_email: no_of_investors_no_email,
      no_of_investors_with_email: no_of_investors_with_email
    }
  end

  # Calculates statistics and filters investor accesses related to user email permissions.
  # When a notification tag is supplied, the approved lists are restricted to contacts
  # that are subscribed to that topic (no tag_list = subscribed to all; tag_list present =
  # subscribed only to intersecting topics). Contacts excluded by tag are surfaced separately.
  #
  # @param model [Object] An instance of Fund, CapitalCall, or CapitalDistribution (used for FundPolicy).
  # @param investor_accesses [ActiveRecord::Relation] Collection of investor accesses.
  # @param tag [String, nil] Notification topic tag (e.g. "CapitalCall"); nil means no filtering.
  # @return [Hash] A hash containing user access counts and specific investor access collections.
  def calculate_user_access_stats(model, investor_accesses, tag: nil)
    # Investor accesses that are not approved
    unapproved_investor_accesses = investor_accesses.unapproved.includes(:user, :granter).distinct

    approved_email_enabled = investor_accesses.approved.email_enabled

    if tag.present?
      # Subscribed: no tag_list at all, or tag_list contains the notification topic
      subscribed_sql = "investor_accesses.tag_list IS NULL OR investor_accesses.tag_list = '' " \
                       "OR investor_accesses.tag_list LIKE ?"
      subscribed      = approved_email_enabled.where(subscribed_sql, "%#{tag}%")
      # Tag-excluded: has a tag_list but it doesn't include this topic — won't receive the notification
      tag_excluded    = approved_email_enabled.where.not(subscribed_sql, "%#{tag}%")
    else
      subscribed   = approved_email_enabled
      tag_excluded = investor_accesses.none
    end

    # Investor accesses that are approved, have email enabled, and are not investor advisors
    approved_investor_access = subscribed.not_investor_advisors.includes(:user, :granter).distinct
    # Investor accesses that are approved, have email enabled, and are investor advisors
    approved_investor_access_ia = subscribed.investor_advisors.includes(:user, :granter).distinct

    # Filter Investor Advisors to ensure they have permission to the fund
    # The same rule the send path applies (Investor#advisor_notifiable?), so the preview counts
    # exactly who will be sent to. It used to carry its own copy, which looked for personal grants
    # in the FUND's entity rather than the investor's and counted any show? - so it could disagree
    # with the send in both directions.
    # Worked example E8 — openspec/changes/fix-advisor-own-investor-access/report.md#verification
    approved_investor_access_ia = approved_investor_access_ia.filter do |ia|
      ia.investor.advisor_notifiable?(ia.user, model)
    end

    # Tag-excluded contacts (both regular and IA) shown as a single "not subscribed" list
    tag_excluded_investor_accesses = tag_excluded.includes(:user, :granter).distinct

    # Number of users who either have email disabled or are not approved
    no_of_users_no_email = investor_accesses.where("email_enabled=? or approved = ?", false, false).count
    # Total number of users with investor access (approved + unapproved/email disabled)
    no_of_users = approved_investor_access.count + approved_investor_access_ia.count + no_of_users_no_email
    # Number of users who have email enabled and are approved
    no_of_users_with_email = no_of_users - no_of_users_no_email

    # Investor accesses that are email disabled
    email_disabled_investor_accesses = investor_accesses.email_disabled.includes(:user, :granter).distinct

    {
      unapproved_investor_accesses: unapproved_investor_accesses,
      approved_investor_access: approved_investor_access,
      approved_investor_access_count: approved_investor_access.count,
      approved_investor_access_ia: approved_investor_access_ia,
      approved_investor_access_ia_count: approved_investor_access_ia.count,
      no_of_users_no_email: no_of_users_no_email,
      no_of_users: no_of_users,
      no_of_users_with_email: no_of_users_with_email,
      email_disabled_investor_accesses: email_disabled_investor_accesses,
      tag_excluded_investor_accesses: tag_excluded_investor_accesses
    }
  end

  def render_number_stats_cards(results_map, card_definitions)
    cards_data = card_definitions.map do |definition|
      stat_value = results_map[definition[:key]]
      {
        path: definition[:path],
        stat: stat_value.respond_to?(:count) ? stat_value.count : stat_value,
        subtitle: definition[:subtitle],
        progress_bar_color: definition[:progress_bar_color],
        text_info: definition[:text_info]
      }
    end

    render(partial: "funds/number_stats_cards", locals: { cards_data: cards_data })
  end

  def setup_fund_selection(current_user, params)
    # Fetch funds
    funds = Pundit.policy_scope(current_user, Fund)
    selected_fund_ids = Array(params[:fund_ids]).presence || []
    [funds, selected_fund_ids]
  end

  # Percentage of committed capital that has been called, clamped to 0..100.
  # Used by the fund card variants to draw deployment bars / donuts.
  def fund_called_pct(fund)
    committed = fund.committed_amount.to_f
    return 0 if committed <= 0

    ((fund.call_amount.to_f / committed) * 100).round.clamp(0, 100)
  end

  # Percentage of called capital that has been returned to investors, clamped to 0..100.
  def fund_distributed_pct(fund)
    called = fund.call_amount.to_f
    return 0 if called <= 0

    ((fund.distribution_amount.abs.to_f / called) * 100).round.clamp(0, 100)
  end

  # Semantic tone for a fund ratio, used to colour the value on the fund cards.
  # Returns one of "good" / "ok" / "poor" / "neutral" so the SCSS can map it to
  # success / warning / danger / primary without the thresholds living in views.
  def fund_ratio_tone(fund_ratio)
    val = fund_ratio.value.to_f
    case fund_ratio.name
    when "XIRR", "IRR", "Gross Portfolio IRR", "Net IRR"
      # IRR-style ratios are percentages
      if val > 15 then "good"
      elsif val > 8 then "ok"
      else "poor"
      end
    when "TVPI", "MOIC", "Value To Cost", "Portfolio Value to Cost", "DPI"
      # Multiples: above 2x is good, above 1x is break-even-plus
      if val > 2.0 then "good"
      elsif val > 1.0 then "ok"
      else "poor"
      end
    else
      "neutral"
    end
  end

  # Short label for a ratio name on compact cards ("Portfolio Value to Cost" -> "Value to Cost")
  def fund_ratio_short_name(fund_ratio)
    fund_ratio.name.sub("Portfolio ", "")
  end

  # Returns the latest values for specified ratios from pre-loaded fund_ratios
  # Expects fund_ratios to be eager-loaded via includes(:fund_ratios) in controller
  def get_latest_fund_ratios(fund, ratio_names = ["Gross Portfolio IRR", "Portfolio Value to Cost", "XIRR", "TVPI"])
    ratios_by_name = {}

    # Filter pre-loaded ratios by name and owner, then group by name
    # If multiple ratios are marked as latest (edge case), use the most recent end_date
    ratios_by_name_group = fund.fund_ratios
                               .where(name: ratio_names, owner: fund).default.latest
                               .group_by(&:name)

    # For each ratio, get the one with the most recent end_date
    ratio_names.each do |name|
      matching_ratios = ratios_by_name_group[name]
      if matching_ratios.present?
        latest_ratio = matching_ratios.max_by { |r| r.end_date || Date.new(0) }
        ratios_by_name[name] = latest_ratio
      end
    end

    ratios_by_name
  end

  # Closed-ended / Open-ended badge for the Funds list, in the same pill style as the fund's tags.
  # Shown only to companies with evergreen funds on, so other companies' lists are unchanged; the type
  # is fixed at creation, so it can't go stale.
  # evergreen_ids: fund ids that have evergreen settings (loaded once by FundsController#index), or nil
  def fund_type_badge(fund, evergreen_ids)
    return unless fund.entity&.permissions&.enable_evergreen_funds?

    # Outside the Funds list (no preloaded ids) ask the fund itself
    open_ended = evergreen_ids ? evergreen_ids.include?(fund.orignal_id || fund.id) : fund.try(:evergreen?)
    fund_type_pill(open_ended)
  end

  # The type pill itself — the Funds list badge and the chosen type on New Fund's step 1 (H5)
  def fund_type_pill(open_ended)
    if open_ended
      tag.span(safe_join([tag.i("", class: "ti ti-infinity me-1"), "Open-ended"]), class: "mb-1 me-1 badge rounded-pill font-medium bg-primary-subtle text-primary")
    else
      tag.span(safe_join([tag.i("", class: "ti ti-lock me-1"), "Closed-ended"]), class: "mb-1 me-1 badge rounded-pill font-medium bg-secondary-subtle text-secondary")
    end
  end

  # H5: the two cards on New Fund's type page — what each type is, in plain words; tone is the card's
  # Bootstrap subtle colour
  def fund_type_cards
    [
      { value: "closed_end", icon: "lock", title: "Closed-ended", tone: "info", tagline: "Commit, call, distribute",
        summary: "Investors commit an amount up front. You draw it with capital calls and return money with distributions over the fund's life.",
        points: ["Commitments, capital calls and distributions", "Investors join at the fund's closes", "A fixed life, then the fund winds down"],
        typical: "Typical: Category I and II AIFs, private equity and venture capital funds",
        steps: "2 steps to set up" },
      { value: "open_ended", icon: "infinity", title: "Open-ended (evergreen)", tone: "success", tagline: "Subscribe and redeem at NAV",
        summary: "Investors subscribe and redeem on dealing dates at the latest NAV. The fund has no end date.",
        points: ["Subscriptions and redemptions on a dealing calendar", "A NAV per unit for each unit class", "Notice periods, lock-ups and redemption gates"],
        typical: "Typical: Category III AIFs, hedge-fund style, tender-offer and interval funds",
        steps: "11 steps to set up · needs a unit type" }
    ]
  end
end
