# Links an approved KYC to evergreen folios created before folios carried one (evergreen-folio-soa ③).
# A folio whose investor has exactly one approved KYC is linked; any other folio (0 or several approved
# KYCs) is listed for a GP to link with the Investing entity picker on the folio page.
#
#   bin/rails evergreen:link_folio_kycs                 # dry run: print what would happen
#   bin/rails evergreen:link_folio_kycs EXECUTE=1       # link
#   bin/rails evergreen:link_folio_kycs FUND_ID=343     # one fund only
#
# Idempotent: linked folios are skipped (E9). Worked examples H6, E7, E8, E9 —
# openspec/changes/evergreen-folio-soa/design.md#worked-examples
namespace :evergreen do
  desc "Link the single approved KYC to evergreen folios without one (dry run unless EXECUTE=1)"
  task link_folio_kycs: :environment do
    execute = ENV["EXECUTE"] == "1"
    puts(execute ? "EXECUTE: linking KYCs" : "DRY RUN: nothing is changed (set EXECUTE=1 to link)")

    funds = Fund.joins(:evergreen_fund_setting)
    funds = funds.where(id: ENV["FUND_ID"]) if ENV["FUND_ID"].present?
    linked = 0
    manual = 0
    funds.find_each do |fund|
      # Only folios still without a KYC (E9: linked ones are skipped)
      fund.capital_commitments.where(investor_kyc_id: nil).includes(:investor).find_each do |folio|
        approved = InvestorKyc.where(entity_id: folio.entity_id, investor_id: folio.investor_id, verified: true).limit(2).pluck(:id)
        if approved.one?
          # H6: unambiguous → link (update! keeps the KYC's commitment counters right)
          puts "#{fund.id} #{fund.name}: #{folio.folio_id} #{folio.investor.investor_name} → KYC #{approved.first}"
          folio.update!(investor_kyc_id: approved.first) if execute
          linked += 1
        else
          # E7 (several) / E8 (none): a person picks on the folio page
          count = approved.empty? ? "0 approved KYCs" : "2 or more approved KYCs"
          puts "#{fund.id} #{fund.name}: #{folio.folio_id} #{folio.investor.investor_name} — #{count}, link on the folio page"
          manual += 1
        end
      end
    end
    puts "#{execute ? 'Linked' : 'Would link'} #{linked}; #{manual} need a manual choice"
  end
end
