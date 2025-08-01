FactoryBot.define do
  factory :task_template do
    for_class { ["CapitalCommitment", "CapitalCall", "CapitalRemittance", "CapitalDistribution", "IndividualKyc", "NonIndividualKyc"].sample }
    tag_list { ["show", "edit", "delete", "list", "approve"].sample }
    details { Faker::Company.catch_phrase }
    due_in_days { rand(3) + 1 }
    action_link { "/tasks" }
    help_link { "/tasks" }
  end

  factory :portfolio_report_extract do
    entity { nil }
    portfolio_report { nil }
    portfolio_report_seaction { nil }
    portfolio_company { nil }
    start_date { "2025-03-03" }
    end_date { "2025-03-03" }
    data { "" }
  end

  factory :portfolio_report_section do
    portfolio_report { nil }
    name { "MyString" }
    data { "MyText" }
  end

  factory :portfolio_report do
    entity { nil }
    name { "MyString" }
    tags { "MyString" }
    include_kpi { false }
    include_portfolio_investments { false }
    extraction_questions { "" }
  end

  factory :excused_investor do
    entity { nil }
    fund { nil }
    folio_id { "MyString" }
    portfolio_company { nil }
    aggregate_portfolio_investment { nil }
    portfolio_investment { nil }
    notes { "MyString" }
  end

  factory :investment do
    entity { Entity.funds.sample}
    portfolio_company { entity.investors.portfolio_companies.sample }
    category { Investment::CATEGORIES.sample }
    investor_name { Faker::Company.name }
    investment_type { Investment::TYPES.sample }
    funding_round { ["A", "B", "C"].sample }
    quantity { rand(1..10) * 100 }
    price_cents { rand(1..10) * 1000000 }
    investment_date { Time.zone.today - rand(130).days }
    notes { Faker::Company.catch_phrase }
    currency { entity.currency }
  end

  factory :ticker_feed do
    ticker { "MyString" }
    price_cents { "9.99" }
    name { "MyString" }
    source { "MyString" }
    for_date { "2024-12-14" }
    for_time { "2024-12-14 12:46:12" }
    price_type { "MyString" }
  end

  factory :viewed_by do
    owner { nil }
    user { nil }
  end

  factory :dashboard_widget do
    name { "MyString" }
    entity { nil }
    owner { nil }
    template { "MyString" }
    position { 1 }
    metadata { "MyText" }
    enabled { false }
  end

  factory :ai_check do
    entity { nil }
    parent { nil }
    owner { nil }
    status { "MyString" }
    explanation { "MyText" }
  end

  factory :ai_rule do
    entity { nil }
    for_class { "MyString" }
    rule { "MyText" }
    tags { "MyString" }
    schedule { "MyString" }
  end

  factory :rm_mapping do
    rm { nil }
    investor { nil }
    entity { nil }
    permissions { 1 }
    approved { false }
  end

  factory :allocation do
    offer { nil }
    interest { nil }
    secondary_sale { nil }
    entity { nil }
    quantity { "9.99" }
    amount { "9.99" }
    notes { "MyText" }
    verified { false }
  end

  factory :key_biz_metric do
    name { Faker::Company.name }
    metric_type { Faker::Company.name }
    value { "9.99" }
    display_value { Faker::Company.name }
    notes { Faker::Company.name }
    query { Faker::Company.catch_phrase }
  end

  factory :incoming_email do
    from { Faker::Company.name }
    to { Faker::Company.name }
    subject { Faker::Company.name }
    body { Faker::Company.catch_phrase }
    owner { nil }
    entity { nil }
  end

  factory :stock_conversion do
    entity { nil }
    portfolio_investment { nil }
    fund { nil }
    from_instrument { nil }
    from_quantity { "9.99" }
    to_instrument { nil }
    to_quantity { "9.99" }
    note { Faker::Company.catch_phrase }
    conversion_date { Date.today - rand(30).days }
  end

  factory :doc_question do
    entity { nil }
    tags { Faker::Company.name }
    question { Faker::Company.catch_phrase }
  end

  factory :support_client_mapping do
    user { nil }
    entity { nil }
    end_date { "2024-04-03" }
  end

  factory :investment_instrument do
    name { (0...8).map { (65 + rand(26)).chr }.join }
    category { "Unlisted" }
    sub_category { "Equity" }
    sector { "Tech" }
    currency { "INR" }
    entity { nil }
    portfolio_company { nil }
  end

  factory :investor_kpi_mapping do
    entity { nil }
    investor { nil }
    reported_kpi_name { Faker::Company.name }
    standard_kpi_name { Faker::Company.name }
    lower_threshhold { "9.99" }
    upper_threshold { "9.99" }
  end

  factory :quick_link_step do
    name { Faker::Company.name }
    link { Faker::Company.catch_phrase }
    description { Faker::Company.catch_phrase }
    entity { nil }
    quick_link { nil }
  end

  factory :quick_link do
    name { Faker::Company.name }
    description { Faker::Company.catch_phrase }
    tags { Faker::Company.name }
    entity { nil }
  end

  factory :custom_notification do
    subject { Faker::Company.name }
    body { Faker::Company.catch_phrase }
    whatsapp { Faker::Company.name }
    entity { nil }
    owner { nil }
  end


  factory :stock_adjustment do
    entity { nil }
    portfolio_company { nil }
    user { nil }
    adjustment { "9.99" }
    notes { Faker::Company.catch_phrase }
  end

  factory :investor_access do
    entity { Entity.sample }
    investor { entity.investors.sample }
    user { nil }
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
    email { Faker::Internet.email }
    phone { rand(10 ** 10) }
    send_confirmation { false }
    approved { true }

  end

  factory :portfolio_cashflow do
    entity { nil }
    fund { nil }
    portfolio_company { nil }
    aggregate_portfolio_investment { nil }
    payment_date { "2023-08-05" }
    amount { "9.99" }
    notes { Faker::Company.catch_phrase }
  end

  factory :call_fee do
    name { Faker::Company.name }
    start_date { "2023-08-03" }
    end_date { "2023-08-03" }
    notes { Faker::Company.name }
    entity { nil }
    fund { nil }
    capital_call { nil }
  end


  factory :kpi do
    entity { nil }
    name { Faker::Company.name }
    value { "9.99" }
    display_value { Faker::Company.name }
    notes { Faker::Company.name }
    kpi_report { nil }
  end

  factory :kpi_report do
    entity { nil }
    as_of { "2023-06-12" }
    notes { Faker::Company.catch_phrase }
    user { nil }
  end


  factory :commitment_adjustment do
    entity { nil }
    fund { nil }
    capital_commitment { nil }
    pre_adjustment { "9.99" }
    amount { "9.99" }
    post_adjustment { "9.99" }
    reason { Faker::Company.catch_phrase }
  end

  factory :fund_unit_setting do
    entity { nil }
    fund { nil }
    name { "A,B,C,D,E,F".split(",").sample }
    management_fee { "9.99" }
    setup_fee { "9.99" }
    gp_units { false }
  end

  factory :fund_formula do
    entity { nil }
    fund { nil }
    name { Faker::Company.buzzword }
    formula { "1+1" }
    rule_type { "GenerateAccountEntry" }
    entry_type { "Test" }
    rule_for { "accounting" }
  end

  factory :portfolio_investment do
    fund { Fund.all.sample }
    entity { fund.entity }
    investment_instrument { entity.investment_instruments.sample }
    portfolio_company { entity.investors.portfolio_companies.sample }
    investment_date { Time.zone.today - 1.month - rand(48).months }
    ex_expenses_base_amount_cents { 10000000 * rand(1..20) }
    quantity { rand(2) > 0 ? 100 * rand(1..10) : -100 * rand(1..10) }
    sub_category { "Equity" }
    category { "Unlisted" }
    sector { InvestmentInstrument::SECTORS[0] }
    notes { Faker::Company.buzzword }
  end

  factory :account_entry do
    capital_commitment { nil }
    entity { nil }
    fund { nil }
    investor { nil }
    folio_id { Faker::Company.name }
    reporting_date { "2023-02-02" }
    entry_type { Faker::Company.name }
    name { Faker::Company.name }
    amount { "9.99" }
    notes { Faker::Company.catch_phrase }
  end

  factory :fund_unit do
    fund { nil }
    capital_commitment { nil }
    investor { nil }
    unit_type { "A,B,C,D,E,F".split(",").sample }
    quantity { 10 }
    reason { Faker::Company.catch_phrase }
  end


  factory :entity_setting do
    pan_verification { false }
    bank_verification { false }
    trial { false }
    trail_end_date { "2023-01-22" }
    valuation_math { Faker::Company.name }
    snapshot_frequency_months { 1 }
    last_snapshot_on { "2023-01-22" }
    # sandbox { true }
    # sandbox_emails { "thimmaiah@gmail.com,ausang@gmail.com" }

  end

  factory :fund_ratio do
    entity { nil }
    fund { nil }
    valuation { nil }
    name { ["XIRR", "TVP", "DVP"].sample }
    value { "9.99" }
    display_value { Faker::Company.name }
    notes { Faker::Company.catch_phrase }
  end

  factory :capital_remittance_payment do
    fund { nil }
    capital_remittance { nil }
    entity { nil }
    amount_cents { "9.99" }
    payment_date { "2023-01-06" }
  end

  factory :user_alert do
    user { nil }
    message { Faker::Company.name }
    entity { nil }
    level { Faker::Company.name }
  end

  factory :esign do
    entity { nil }
    user { nil }
    owner { nil }
    sequence_id { 1 }
    link { Faker::Company.name }
    reason { Faker::Company.catch_phrase }
    status { Faker::Company.name }
    completed { false }
  end

  factory :signature_workflow do
    owner { nil }
    entity { nil }
    signatory_ids { Faker::Company.name }
    completed_ids { Faker::Company.name }
    sequential { false }
  end

  factory :adhaar_esign do
    entity { nil }
    document { nil }
    esign_url { Faker::Company.catch_phrase }
    esign_doc_id { Faker::Company.name }
    signed_file_url { Faker::Company.catch_phrase }
    is_signed { false }
    reponse { Faker::Company.catch_phrase }
  end

  factory :investor_notice_entry do
    investor_notice { nil }
    entity { nil }
    investor { nil }
    investor_entity_id { nil }
    active { false }
  end

  factory :investor_notice do
    entity { nil }
    investor { nil }
    investor_entity_id { nil }
    start_date { "2022-11-07" }
    end_date { "2022-11-07" }
    active { false }
  end

  factory :fee do
    advisor_name { Faker::Company.name }
    amount { "9.99" }
    amount_label { Faker::Company.name }
    owner { nil }
    entity { nil }
  end


  factory :investor_kyc do
    # entity { Entity.where(enable_kycs: true).sample }
    investor { entity.investors.sample if entity }
    full_name { Faker::Name.name }
    residency { ["domestic", "foreign"].sample }
    PAN { [*('A'..'Z'),*('0'..'9')].shuffle[0,10].join }
    address { Faker::Address.full_address }
    corr_address { Faker::Address.full_address }
    bank_account_number  {Faker::Bank.account_number}
    bank_name {Faker::Bank.name}
    bank_branch {Faker::Address.city}
    bank_account_type { ["Savings", "Current"].sample }
    ifsc_code {Faker::Bank.swift_bic}
    birth_date { Time.zone.today - rand(36).years }
    expiry_date { Time.zone.today + rand(36).months }
    comments { Faker::Company.buzzword }
  end

  factory :aml_report do
    entity { FactoryBot.create(:entity) }
    investor { FactoryBot.create(:investor, entity: entity) }
    investor_kyc { FactoryBot.create(:investor_kyc, entity: entity, investor: investor) }
    name { Faker::Name.name }
    match_status { "potential_match" }
    approved { true }
    approved_by_id {FactoryBot.create(:user, entity: entity).id}
    associates { {Faker::Name.name =>"child", Faker::Name.name =>"spouse"}.to_s }
    fields  {
    {"Nationality"=>
    [{"name"=>"Nationality", "source"=>"hm-treasury-list", "value"=>"Russian Federation"},
     {"name"=>"Nationality", "source"=>"ofac-sdn-list", "value"=>"Russian Federation"}]}
    }
    types  {"pep, pep-class-1, pep-class-2, sanction, fitness-probity, adverse-media, adverse-media-general"}
    source_notes  {
    [{"internal-adverse-media"=>
    {"name"=>"internal Adverse Media",
     "aml_types"=>
      ["adverse-media",
       "adverse-media-financial-crime",
       "adverse-media-fraud",
       "adverse-media-general",
       "adverse-media-narcotics",
       "adverse-media-terrorism",
       "adverse-media-violent-crime"],
     "country_codes"=>["PL", "RU", "UA", "US"]}}]
    }
    response{"response json here"}
  end


  factory :capital_distribution_payment do
    fund { nil }
    entity { nil }
    capital_distribution { nil }
    investor { nil }
    form_type { nil }
    amount { "9.99" }
    payment_date { "2022-09-04" }
    properties { Faker::Company.catch_phrase }
  end


  factory :capital_distribution do
    fund { Fund.all.sample }
    entity { fund.entity }
    income { 1000000 * rand(1..5) }
    cost_of_investment_cents { gross_amount * 0.8 }
    reinvestment { gross_amount * 0.5 }
    distribution_date { Date.today + rand(5).weeks }
    title { "Capital Dist #{Time.now.to_f}" }
    unit_prices {
      fund.unit_types.split(",").map{|ut| [ut.strip, 100 * (rand(2) + 1)]}.to_h if fund.unit_types
    }
  end

  factory :capital_remittance do
    capital_call { CapitalCall.all.sample }
    fund { capital_call.fund }
    entity { fund.entity }
    investor { fund.investors.sample }
    status { ["Pending", "Paid"].sample }
    collected_amount { 10000 * rand(10..20) }
    notes { Faker::Company.catch_phrase  }
  end

  factory :capital_call do
    fund { Fund.all.sample }
    entity { fund.entity }
    due_date { Time.zone.today + 3.weeks }
    call_date { Time.zone.today + 3.weeks }
    name { "Capital Call #{Time.now.to_f}" }
    call_basis { "Percentage of Commitment" }
    percentage_called { rand(1..4) * 10 }
    fund_closes { ["All"] }
    close_percentages { {"First Close"=> rand(1..4) * 10} }
    notes { Faker::Company.catch_phrase }
    unit_prices {
      fund.unit_types.split(",").map{|ut| [ut.strip, "price" => 100 * (rand(2) + 1), "premium" => 10 * (rand(2) + 1) ]}.to_h if fund.unit_types
    }
  end

  factory :capital_commitment do
    fund { Fund.all.sample }
    unit_type { fund.unit_types.split(",").sample }
    entity { fund.entity }
    investor { entity.investors.sample }
    folio_committed_amount_cents { 10000000 * rand(10..30) }
    folio_id {rand(100**4)}
    folio_currency { fund.currency }
    fund_close { "First Close" }
    notes { Faker::Company.catch_phrase }
    commitment_date { Date.today - rand(24).months }
  end

  factory :fund do
    name { ["Tech", "Agri", "FinTech", "SaaS", "Macro", "HealthTech", "EdTech", "Biotech", "E-commerce", "AI/ML", "Clean Energy", "PropTech", "IoT", "Cybersecurity", "Cloud Computing", "Digital Payments", "Blockchain", "Mobility", "Smart Cities", "Robotics", "Renewable Energy", "Telecommunications", "Data Analytics", "InsurTech", "AgriTech", "GreenTech", "MedTech", "LegalTech", "Logistics", "RegTech"].sample + " Fund" }
    details { Faker::Company.catch_phrase }
    entity { Entity.funds.sample }
    tag_list {  }
    unit_types {"Series A, Series B, Series C"}
    currency { ["INR"].sample }
    json_fields { {from_email: "#{name.parameterize}@#{entity.name.parameterize}.com"} }
  end


  factory :expression_of_interest do
    investment_opportunity { InvestmentOpportunity.all.sample }
    entity { investment_opportunity.entity }
    investor { entity.investors.sample }
    eoi_entity { investor.investor_entity }
    user { eoi_entity.employees.sample }
    amount_cents { 10e6 * rand(50..100) }
    approved { false }
    verified { false }
    details { Faker::Company.catch_phrase  }
  end

  IO_TAGS = ["Fintech", "Seed", "Pre Series A", "Bridge", "SAAS", "AgriTech", "eCommerce", "Health Tech"]
  factory :investment_opportunity do
    entity { Entity.funds.sample }
    company_name { Faker::Company.name }
    fund_raise_amount { 10e7 }
    valuation { 10e9 }
    min_ticket_size { 10e5 }
    last_date { Date.today + 1.month }
    currency { entity.currency }
    tag_list { [IO_TAGS.sample, IO_TAGS.sample].join(",") }
    details { Faker::Company.catch_phrase  }
    json_fields { {from_email: "#{company_name.parameterize}@#{entity.name.parameterize}.com"} }
  end

  factory :approval do
    title { Faker::Company.buzzword }
    due_date { Time.zone.today + 7.days }
    agreements_reference { Faker::Company.catch_phrase }
    entity { Entity.startups.sample }
    approved_count { 0 }
    rejected_count { 0 }
    response_status { "Approved,Rejected,Pending"}
  end

  factory :e_signature do
    entity { Entity.startups.sample }
    document { FactoryBot.create(:document, entity: entity) }
    email { Faker::Internet.email }
    position { rand(5) + 1 }
    signature_type { ["Aadhaar", "Electronic"][rand(2)] }
    status { "" }
  end

  factory :reminder do
    entity { nil }
    owner { nil }
    unit { Faker::Company.name }
    count { 1 }
    sent { false }
  end

  factory :permission do
    user { User.all.sample }
    owner { Document.all.sample }
    email { user.email }
    permissions { [:read, :write] }
    entity { owner.entity }
    granted_by { owner.entity.employees.sample }
  end

  factory :task do
    details { Faker::Company.catch_phrase }
    entity { Entity.startups.sample }
    for_entity { entity.all.sample }
    owner {for_entity}
    completed { rand(2) }
    user { entity.employees.all.sample }
  end

  factory :valuation do
    category { "Unlisted" }
    sub_category { "Equity" }
    valuation_date { Date.today - rand(48).months }
    valuation_cents { rand(1..10) * 100000000 }
    per_share_value_cents { rand(1..10) * 100000 }
    report { File.new("public/img/whatsappQR.png", "r") }
  end

  factory :scenario do
    name { Faker::Company.name }
    entity { nil }
  end


  factory :payment do
    entity { Entity.all.sample }
    amount { rand(100)*10 + rand(100) * 10 }
    plan { Entity::PLANS[rand(Entity::PLANS.length)] }
    discount { 0 }
    reference_number { (0...8).map { (65 + rand(26)).chr }.join }
    user { entity.employees.sample }
  end



  factory :interest do
    buyer_entity_name {Faker::Company.name}
    address {Faker::Address.street_address}
    city {Faker::Address.city.truncate(20)}
    demat {Faker::Number.number(digits: 10)}
    contact_name {Faker::Name.name}
    email {Faker::Internet.email}
    PAN { [*('A'..'Z'),*('0'..'9')].shuffle[0,10].join }
    buyer_signatory_emails {Faker::Internet.email}
  end


  factory :offer do
    PAN { [*('A'..'Z'),*('0'..'9')].shuffle[0,10].join }
    address { Faker::Address.full_address }
    city {Faker::Address.city.truncate(20)}
    demat {Faker::Number.number(digits: 10)}
    bank_account_number  {Faker::Bank.account_number}
    bank_name {Faker::Bank.name}
    bank_routing_info {Faker::Bank.routing_number}
    full_name {Faker::Name.first_name + " " + Faker::Name.last_name}
    ifsc_code {Faker::Bank.swift_bic}
    seller_signatory_emails {Faker::Internet.email}
  end

  factory :secondary_sale do
    name { "Sale-#{Time.zone.today}" }
    entity { nil }
    start_date { Time.zone.today }
    offer_end_date { start_date + 1.week }
    end_date { start_date + (2 + rand(10)).days }
    percent_allowed { (1 + rand(9)) * 10 }
    min_price { (1 + rand(9)) * 1000 }
    max_price { min_price + (1 + rand(9)) * 1000 }
    active { true }
    support_email {"support@nowhere.com"}
  end



  factory :folder do
    name { Faker::File.dir }
    entity { Entity.all.sample }
    folder_type { :regular }
  end

  factory :document do
    name { "Fact Sheet,Cap Table,Latest Financials,Conversion Stats,Deal Sheet".split(",").sample }
    text { Faker::Company.catch_phrase }
    entity { Entity.all.sample }
    file { File.new("public/img/whatsappQR.png", "r") }
    folder { Folder.first }
  end


  factory :message do
    user {  }
    content { Faker::Company.catch_phrase }
  end

  factory :deal_activity do
    title { Faker::Company.catch_phrase }
    details { Faker::Company.catch_phrase }
    deal { Deal.all.sample }
    deal_investor { deal.deal_investors.sample }
    by_date { Date.today + rand(10).days }
    # status is now an enum
    status { ["Incomplete", "Completed"][rand(2)] }
    completed { [true, false][rand(2)] }
    entity_id { deal.entity_id }
  end

  factory :deal_investor do
    deal { Deal.all.sample }
    investor { deal.entity.investors.sample }
    status { DealInvestor::STATUS[rand(DealInvestor::STATUS.length)] }
    primary_amount_cents { rand(3..11) * 100_000_000 }
    pre_money_valuation_cents { rand(3..11) * 100_000_000 }
    secondary_investment_cents { rand(3..11) * 100_000_000 }
    entity { deal.entity }
    company_advisor { Faker::Company.name }
    investor_advisor { Faker::Company.name }
    tier { ["1", "2", "3"][rand(3)] }
    fee { rand(1..10) * 1000 }
    tags { ["Lead", "Co-Investor", "Follow-on"][rand(3)] }
    deal_lead { Faker::Name.name }
    source { Faker::Name.name }
    notes { Faker::Company.catch_phrase }
  end

  factory :deal do
    entity { Entity.startups.all.sample }
    name { ["Series A", "Series B", "Series C", "Series D"][rand(4)] }
    amount { rand(2..10) * 10_000_000_000 }
    status { "Open" }
    currency { entity.currency }
    units { entity.units }
    start_date { Date.today + rand(5).days }
  end

  factory :note do
    investor { Investor.all.sample }
    details {
      [
        "investor is keen on the space; have invested in peers globally",
        "investment size over $75m",
        "want to see positive cash flows ",
        "Meeting rescheduled 4 times; led by analyst and MD didn't show up",
        "Want to track company for 3-4 quarters before investing ",
        "Very keen on the space; have met all the peers and will come in for primary or secondary at short notice ",
        "Partner is alumni from business school and a techie at heart",
        "IC will focus on customer acquisition and market share gains over revenue / profitability ",
        "Sweet spot of $20-40million investment; this is a high conviction sector for them",
        "Arrogant investor; thinks we won't survive  ",
        "Invested in peers; probably fishing for information ",
        "High energy team; have offered to make introductions with the Silicon valley biggies for US roll-out"
      ].sample
    }
    entity_id { investor.entity_id }
    user { investor.entity.employees.sample }
    on { Time.now - rand(120).days }
    created_at {Time.now - rand(120).days}
  end


  factory :investor do
    investor_entity_id { Entity.startups.sample.id }
    investor_name { investor_entity.name }
    entity_id { Entity.startups.sample.id }
    # pan { investor_entity.pan }
    primary_email { investor_entity.primary_email }
    category { ["Lead Investor", "Co-Investor"][rand(2)] }
    city {Faker::Address.city.truncate(20)}
  end

  factory :user do
    entity { Entity.all.sample }
    first_name { Faker::Name.first_name }
    last_name  { Faker::Name.last_name }
    email { entity ? "#{first_name.downcase}@#{entity.name.parameterize}.com" : Faker::Internet.email }
    password { "password" }
    phone { rand(10 ** 10) }
    confirmed_at { Time.zone.now }
    accept_terms {true}
    permissions {User.permissions.keys}
  end

  factory :entity do
    name { Faker::Company.name }
    # pan { [*('A'..'Z'),*('0'..'9')].shuffle[0,10].join }
    primary_email { Faker::Internet.email }
    category { Faker::Company.industry }
    url { "https://#{Faker::Internet.domain_name}" }
    entity_type { Entity::TYPES[rand(Entity::TYPES.length)] }
    enable_documents {true}
    enable_deals {true}
    enable_investments {true}
    enable_holdings {true}
    enable_secondary_sale {true}
    enable_captable {true}
    enable_funds {true}
    enable_account_entries {true}
    enable_units {true}
    enable_inv_opportunities {true}
    enable_fund_portfolios {true}
    enable_kycs {true}
    enable_kpis {true}
    enable_approvals {true}
    enable_investors {true}
    currency { ENV["CURRENCY"].split(",")[rand(3)] }
    units { ENV["CURRENCY_UNITS"].split(",")[rand(3)] }

    trait :with_exchange_rates do
      after(:create) do |entity|
        ExchangeRate.create([
            {from: "USD", to: "INR", rate: 81.72, entity:},
            {from: "INR", to: "USD", rate: 0.012, entity:}
        ])
      end
    end
  end

  factory :doc_share do
    document {Document.first} # Ensure a document is created and associated
    email { Faker::Internet.email }
    email_sent { false }
    view_count { 0 }
  end
end
