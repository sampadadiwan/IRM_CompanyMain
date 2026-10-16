# Tabler icon for an investor category's stat card (Stakeholders page).
# Categories are dynamic — the ENV default list, a per-entity override
# (entity.investor_categories) and any legacy values still stored — so the standard
# names plus common industry categories are mapped, and anything else falls back to
# one neutral icon.
module InvestorCategoryIconHelper
  # Keys are normalised (see normalise_investor_category); values are Tabler icon
  # names without the "ti-" prefix
  INVESTOR_CATEGORY_ICONS = {
    # Standard CapHive categories (ENV INVESTOR_CATEGORIES + extras seen in data)
    "lp" => "users",
    "limitedpartner" => "users",
    "gp" => "building-bank",
    "generalpartner" => "building-bank",
    "leadinvestor" => "crown",
    "coinvestor" => "users-group",
    "board" => "armchair",
    "boardmember" => "armchair",
    "founder" => "bulb",
    "promoter" => "bulb",
    "employee" => "id-badge",
    "management" => "id-badge",
    "rm" => "user-star",
    "relationshipmanager" => "user-star",
    "wealthmanager" => "wallet",
    "prospective" => "user-search",
    "prospect" => "user-search",
    "portfoliocompany" => "building",
    "investee" => "building",
    "portfolio" => "chart-pie",
    "advisor" => "briefcase",
    "adviser" => "briefcase",
    "consultant" => "briefcase",
    "investor" => "user-check",
    "fund" => "coins",
    "domestic" => "map-pin",
    "foreign" => "world",
    # Investor types common across the industry
    "familyoffice" => "home-heart",
    "multifamilyoffice" => "home-heart",
    "hni" => "user-dollar",
    "hnwi" => "user-dollar",
    "uhni" => "user-dollar",
    "uhnwi" => "user-dollar",
    "individual" => "user-dollar",
    "nri" => "world",
    "fpi" => "world",
    "fii" => "world",
    "angel" => "seeding",
    "angelinvestor" => "seeding",
    "institutional" => "building-skyscraper",
    "institutionalinvestor" => "building-skyscraper",
    "corporate" => "briefcase-2",
    "corporateinvestor" => "briefcase-2",
    "strategic" => "briefcase-2",
    "strategicinvestor" => "briefcase-2",
    "bank" => "building-bank",
    "insurance" => "shield-check",
    "insurancecompany" => "shield-check",
    "pensionfund" => "pig-money",
    "endowment" => "school",
    "foundation" => "heart-handshake",
    "sovereignwealthfund" => "flag",
    "swf" => "flag",
    "fundoffunds" => "stack-2",
    "fof" => "stack-2",
    "dfi" => "building-arch",
    "developmentfinanceinstitution" => "building-arch",
    "venturecapital" => "target-arrow",
    "vc" => "target-arrow",
    "privateequity" => "target-arrow",
    "pe" => "target-arrow",
    "lender" => "cash",
    "debtinvestor" => "cash",
    "syndicate" => "users-group",
    "accelerator" => "ladder",
    "incubator" => "ladder",
    "trust" => "user-shield",
    # Service providers often kept as stakeholders
    "trustee" => "file-certificate",
    "custodian" => "user-shield",
    "legal" => "gavel",
    "lawyer" => "gavel",
    "legalcounsel" => "gavel",
    "auditor" => "calculator",
    "accountant" => "calculator",
    "ca" => "calculator",
    "placementagent" => "users-plus",
    "distributor" => "users-plus"
  }.freeze

  INVESTOR_CATEGORY_FALLBACK_ICON = "tag".freeze

  def investor_category_icon(category)
    key = normalise_investor_category(category)
    # Exact match first, then the singular form so "LPs" / "Family Offices" still map
    INVESTOR_CATEGORY_ICONS[key] || INVESTOR_CATEGORY_ICONS[key.delete_suffix("s")] || INVESTOR_CATEGORY_FALLBACK_ICON
  end

  private

  # "Co-Investor", "co investor" and "CoInvestor" all become "coinvestor"
  def normalise_investor_category(category)
    category.to_s.downcase.gsub(/[^a-z0-9]/, "")
  end
end
