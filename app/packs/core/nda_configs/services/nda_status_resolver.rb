# frozen_string_literal: true

# Resolves the full NDA status picture for a given NDA config and folder.
# Batches four read queries to avoid N+1:
#   1. InvestorAccess → investor universe for the entity
#   2. InvestorAccess → users per investor (with user preloaded, includes exempt_from_nda)
#   3. NdaAcceptance → latest acceptance per investor (MySQL GROUP BY + MAX)
#   4. NdaSignatory → signatory user_ids for this NDA config
#
# Changed: Removed NdaExemption query — exemption is now a boolean on InvestorAccess.
# Why: Per product decision (2026-10-05) — exemption is stakeholder-level, not user-level.
#
# @see NdaStatusController
# @see NdaConfig
# @see NdaAcceptance
# @see NdaSignatory
class NdaStatusResolver
  # @param nda_config [NdaConfig] the NDA config to resolve status for
  # @param folder [Folder] the folder whose access rights define the investor universe
  # @return [Hash] structured status data with :counters and :investor_rows
  def self.resolve(nda_config, folder)
    new(nda_config, folder).resolve
  end

  # @param nda_config [NdaConfig] the NDA config to resolve status for
  # @param folder [Folder] the folder whose access rights define the investor universe
  def initialize(nda_config, folder)
    @nda_config = nda_config
    @folder = folder
  end

  # @return [Hash] with :counters (Hash) and :investor_rows (Array of Hashes)
  def resolve
    investors = resolve_investors
    return empty_result if investors.empty?

    investor_ids = investors.map(&:id)
    users_by_investor = resolve_users(investor_ids)
    acceptances_by_investor = resolve_latest_acceptances(investor_ids)
    signatory_user_ids = resolve_signatory_user_ids

    investor_rows = build_investor_rows(investors, users_by_investor, acceptances_by_investor, signatory_user_ids)
    counters = compute_counters(investor_rows)

    { counters: counters, investor_rows: investor_rows }
  end

  private

  # Resolves the investor universe from InvestorAccess for the NDA config's entity.
  # Changed: Uses InvestorAccess instead of AccessRight to determine investor universe.
  # Why: Data Room folder visibility for LPs is driven by InvestorAccess (entity-level),
  #   not by AccessRight (folder-level). The NDA gate also resolves investors via
  #   InvestorAccess, so the dashboard must use the same source for consistency.
  #
  # @return [Array<Investor>] all investors with approved InvestorAccess to this entity
  def resolve_investors
    investor_ids = InvestorAccess
      .where(entity_id: @nda_config.entity_id, approved: true)
      .distinct
      .pluck(:investor_id)

    Investor.where(id: investor_ids)
  end

  # @param investor_ids [Array<Integer>] investor IDs to resolve users for
  # @return [Hash{Integer => Array<InvestorAccess>}] investor_id → InvestorAccess records (with user preloaded)
  def resolve_users(investor_ids)
    InvestorAccess
      .where(entity_id: @nda_config.entity_id, investor_id: investor_ids, approved: true)
      .includes(:user)
      .group_by(&:investor_id)
  end

  # Fetches the latest NdaAcceptance per investor using MySQL-compatible GROUP BY + MAX subquery.
  #
  # @param investor_ids [Array<Integer>] investor IDs to check acceptances for
  # @return [Hash{Integer => NdaAcceptance}] investor_id → latest NdaAcceptance
  def resolve_latest_acceptances(investor_ids)
    return {} if investor_ids.empty?

    # MySQL-compatible: subquery finds max created_at per investor, outer query fetches full records
    subquery = NdaAcceptance
      .where(nda_config_id: @nda_config.id, investor_id: investor_ids)
      .group(:investor_id)
      .select("investor_id, MAX(created_at) AS max_created_at")

    NdaAcceptance
      .joins("INNER JOIN (#{subquery.to_sql}) latest ON nda_acceptances.investor_id = latest.investor_id AND nda_acceptances.created_at = latest.max_created_at")
      .where(nda_config_id: @nda_config.id)
      .includes(:user)
      .index_by(&:investor_id)
  end

  # Changed: Added signatory batch query replacing per-row tag_list check.
  # Why: Signatories are now stored in nda_signatories table (per-NDA scoped)
  #   instead of the entity-wide InvestorAccess tag_list field.
  #
  # @return [Set<Integer>] user_ids designated as signatories for this NDA config
  def resolve_signatory_user_ids
    NdaSignatory.where(nda_config_id: @nda_config.id).pluck(:user_id).to_set
  end

  # @param investors [Array<Investor>] the investor universe
  # @param users_by_investor [Hash{Integer => Array<InvestorAccess>}] investor_id → user records
  # @param acceptances_by_investor [Hash{Integer => NdaAcceptance}] investor_id → latest acceptance
  # @param signatory_user_ids [Set<Integer>] set of designated signatory user IDs
  # @return [Array<Hash>] investor rows with nested user detail
  def build_investor_rows(investors, users_by_investor, acceptances_by_investor, signatory_user_ids)
    investors.map do |investor|
      investor_accesses = users_by_investor[investor.id] || []
      acceptance = acceptances_by_investor[investor.id]

      # Changed: Exemption read from InvestorAccess.exempt_from_nda boolean.
      # Why: Stakeholder-level exemption replaces user-level NdaExemption table.
      any_exempt = investor_accesses.any? { |ia| ia.exempt_from_nda? }

      user_rows = investor_accesses.map do |ia|
        user = ia.user
        is_signer = acceptance&.user_id == user.id && acceptance&.accepted?
        nda_tagged = signatory_user_ids.include?(user.id)

        user_status = if is_signer
                        "Signer"
                      else
                        "—"
                      end

        {
          user: user,
          status: user_status,
          nda_tagged: nda_tagged,
          signer: is_signer
        }
      end

      investor_status = if any_exempt
                          "Exempt"
                        elsif acceptance&.accepted?
                          "Accepted"
                        elsif acceptance&.declined?
                          "Declined"
                        else
                          "Pending"
                        end

      {
        investor: investor,
        status: investor_status,
        signed_by: acceptance&.accepted? ? acceptance.user : nil,
        signed_at: acceptance&.accepted? ? acceptance.created_at : nil,
        users: user_rows
      }
    end
  end

  # @param investor_rows [Array<Hash>] investor rows with :status
  # @return [Hash{Symbol => Integer}] counts per status
  def compute_counters(investor_rows)
    { accepted: 0, pending: 0, declined: 0, exempt: 0 }.tap do |c|
      investor_rows.each do |row|
        case row[:status]
        when "Accepted" then c[:accepted] += 1
        when "Pending"  then c[:pending] += 1
        when "Declined" then c[:declined] += 1
        when "Exempt"   then c[:exempt] += 1
        end
      end
    end
  end

  # @return [Hash] empty result when no investors have folder access
  def empty_result
    { counters: { accepted: 0, pending: 0, declined: 0, exempt: 0 }, investor_rows: [] }
  end
end
