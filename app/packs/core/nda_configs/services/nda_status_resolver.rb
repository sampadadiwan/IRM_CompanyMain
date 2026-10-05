# frozen_string_literal: true

# Resolves the full NDA status picture for a given NDA config and folder.
# Batches four read queries to avoid N+1:
#   1. AccessRight → investor universe for the folder
#   2. InvestorAccess → users per investor + NDA tags
#   3. NdaAcceptance → latest acceptance per investor (MySQL GROUP BY + MAX)
#   4. NdaExemption → exempt user_ids
#
# Returns structured data for both the modal summary and the AG Grid JSON endpoint.
#
# @see NdaStatusController
# @see NdaConfig
# @see NdaAcceptance
# @see NdaExemption
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
    exempt_user_ids = resolve_exempt_user_ids

    investor_rows = build_investor_rows(investors, users_by_investor, acceptances_by_investor, exempt_user_ids)
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

  # @return [Set<Integer>] user_ids that are exempt from this NDA config
  def resolve_exempt_user_ids
    NdaExemption.where(nda_config_id: @nda_config.id).pluck(:user_id).to_set
  end

  # @param investors [Array<Investor>] the investor universe
  # @param users_by_investor [Hash{Integer => Array<InvestorAccess>}] investor_id → user records
  # @param acceptances_by_investor [Hash{Integer => NdaAcceptance}] investor_id → latest acceptance
  # @param exempt_user_ids [Set<Integer>] set of exempt user IDs
  # @return [Array<Hash>] investor rows with nested user detail
  def build_investor_rows(investors, users_by_investor, acceptances_by_investor, exempt_user_ids)
    investors.map do |investor|
      investor_accesses = users_by_investor[investor.id] || []
      acceptance = acceptances_by_investor[investor.id]

      user_rows = investor_accesses.map do |ia|
        user = ia.user
        is_signer = acceptance&.user_id == user.id && acceptance&.accepted?
        is_exempt = exempt_user_ids.include?(user.id)
        nda_tagged = ia.tag_list.to_s.include?("NDA")

        user_status = if is_exempt
                        "Exempt"
                      elsif is_signer
                        "Signer"
                      else
                        "—"
                      end

        {
          user: user,
          status: user_status,
          nda_tagged: nda_tagged,
          exempt: is_exempt,
          signer: is_signer
        }
      end

      all_exempt = investor_accesses.any? && investor_accesses.all? { |ia| exempt_user_ids.include?(ia.user_id) }

      investor_status = if all_exempt
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
