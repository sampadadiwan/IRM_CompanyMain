# Demo deal seed for DealManagementAgent testing — entity 157
#
# Creates two fully-populated open deals:
#
#   Deal 1: "Series B — Horizon Analytics (Demo)"
#     4 investors: Active+progressing, Active+stagnant, Pending+upcoming reminders, Declined
#     Data room: 5 documents (IM, Financial Model, Cap Table, NDA, Term Sheet)
#     Per-investor docs + completed-activity attachments
#
#   Deal 2: "Seed Round — NovaTech Ventures (Demo)"
#     3 investors: Active+progressing, Active+overdue, Declined
#     Data room: 3 documents
#     Per-investor docs
#
# Run with:
#   bundle exec rails runner db/seeds/deal_management_agent_demo_157.rb
#
# Idempotent — tears down and recreates only the two demo deals (by name).
# All other entity data is untouched.

require "faker"

ENTITY_ID    = 157
NOTIFY_EMAIL = "fund-ops@example.com"

DEMO_DEALS = [
  "Series B — Horizon Analytics (Demo)",
  "Seed Round — NovaTech Ventures (Demo)"
].freeze

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def log(msg)
  puts "[deal_demo] #{msg}"
end

def sample_file(filename)
  path = Rails.root.join("public/sample_uploads/#{filename}")
  raise "Sample file not found: #{path}" unless File.exist?(path)
  File.open(path, "r")
end

def attach_doc(owner:, name:, filename:, user:, entity:, folder: nil)
  doc = Document.new(
    entity:     entity,
    owner:      owner,
    name:       name,
    user:       user,
    send_email: false
  )
  doc.folder = folder || owner.document_folder
  doc.file   = sample_file(filename)
  doc.save!
  log "    doc '#{name}' → #{owner.class}##{owner.id}"
  doc
rescue StandardError => e
  log "    WARN: could not attach '#{name}': #{e.message}"
  nil
end

# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------

entity = Entity.find(ENTITY_ID)
admin  = entity.employees.first
raise "No employees for entity #{ENTITY_ID}" if admin.nil?

log "Entity: #{entity.name} (id=#{ENTITY_ID}), admin=#{admin.email}"

Chewy.strategy(:bypass) do

# Tear down previous demo runs
DEMO_DEALS.each do |deal_name|
  Deal.unscoped.where(entity_id: ENTITY_ID, name: deal_name).each do |d|
    log "Destroying existing deal '#{d.name}' (id=#{d.id})"
    d.deal_investors.each(&:destroy!)
    d.destroy!
  end
end

# Resolve investors — we need at least 7 (4 for deal 1 + 3 for deal 2)
available_investors = entity.investors
                            .not_portfolio_companies
                            .not_advisors
                            .not_rms
                            .limit(20)
                            .to_a

raise "Need ≥7 LP/VC investors in entity #{ENTITY_ID} — found #{available_investors.size}" if available_investors.size < 7

# ---------------------------------------------------------------------------
# Shared activity template list
# ---------------------------------------------------------------------------

DEAL_STEPS = [
  # title,                           days
  ["Info Deck Sent",                   5],
  ["NDA Executed",                    10],
  ["Management Presentation",         20],
  ["Financial Due Diligence",         35],
  ["Legal Due Diligence",             50],
  ["Term Sheet Issued",               60],
  ["Term Sheet Countersigned",        70],
  ["Board Approval",                  80],
  ["Definitive Docs (SHA/SSA/SPA)",   90],
  ["Remittance & Closing",           100],
].freeze

def create_activity_templates(deal, entity)
  deal.deal_activities.where(deal_investor_id: nil).destroy_all
  DEAL_STEPS.each_with_index do |(title, days), idx|
    DealActivity.create!(
      deal:             deal,
      deal_investor_id: nil,
      entity:           entity,
      status:           "Template",
      title:            title,
      sequence:         idx + 1,
      days:             days
    )
  end
  log "  #{DEAL_STEPS.size} activity templates created"
end

def create_investor(deal:, entity:, investor:, status:, amount:, tier:, lead:, source:, tags:, notes:)
  di = DealInvestor.new(
    deal:                      deal,
    investor:                  investor,
    entity:                    entity,
    status:                    status,
    primary_amount_cents:      amount,
    pre_money_valuation_cents: 200_000_000_00,
    tier:                      tier,
    deal_lead:                 lead,
    source:                    source,
    tags:                      tags
  )
  di.save!
  di.notes = notes
  di.save!
  di.create_activities
  di.reload
  log "  DealInvestor##{di.id} #{investor.investor_name} [#{status}] — #{di.deal_activities.count} activities"
  di
end

def complete_steps(di, deal, titles)
  titles.each do |title|
    act = di.deal_activities.find_by(title: title)
    next unless act
    act.update!(status: "Complete", by_date: deal.start_date + act.days)
    log "    ✓ #{title}"
  end
end

def set_by_dates(di, deal)
  di.deal_activities.where.not(status: %w[Complete complete]).each do |act|
    act.update!(by_date: deal.start_date + act.days)
  end
end

def backdate_stagnant(di, days)
  DealInvestor.where(id: di.id).update_all(updated_at: days.days.ago)
  DealActivity.where(deal_investor_id: di.id).update_all(updated_at: days.days.ago)
  log "  Backdated #{di.investor_name} (stagnant: #{days}d)"
end

def make_overdue(di, title, days_ago)
  act = di.deal_activities.find_by(title: title)
  return unless act
  act.update!(status: "Incomplete", by_date: days_ago.days.ago.to_date)
  log "    ⚠ #{title} overdue by #{days_ago}d"
end

def make_upcoming(di, title, days_from_now)
  act = di.deal_activities.find_by(title: title)
  return unless act
  act.update!(status: "Incomplete", by_date: days_from_now.days.from_now.to_date)
  log "    ⏰ #{title} due in #{days_from_now}d"
end

# ============================================================================
# DEAL 1 — Series B
# ============================================================================
log "\n═══ Deal 1: Series B — Horizon Analytics ═══"

deal1 = Deal.new(
  entity:       entity,
  name:         "Series B — Horizon Analytics (Demo)",
  status:       "Open",
  amount_cents: 50_000_000_00,
  currency:     "USD",
  start_date:   90.days.ago.to_date,
  end_date:     60.days.from_now.to_date,
  tags:         "SaaS,B2B,Series B",
  units:        "shares"
)
CreateDeal.wtf?(deal: deal1)
raise "CreateDeal failed: #{deal1.errors.full_messages.join(', ')}" unless deal1.persisted?
log "Created Deal##{deal1.id}: #{deal1.name}"

create_activity_templates(deal1, entity)

# ── Deal 1 data room ──────────────────────────────────────────────────────────
data_room1 = deal1.deal_documents_folder
[
  ["Information Memorandum",  "Offer_1_SPA.pdf"                    ],
  ["Financial Model",         "CashFlow.xlsx"                       ],
  ["Cap Table",               "CRISIL Report.xlsx"                  ],
  ["NDA Template",            "Mutual-Confidentiality-Agreement.docx"],
  ["Draft Term Sheet",        "SPA.docx"                           ],
].each do |(name, file)|
  attach_doc(owner: deal1, name: name, filename: file, user: admin, entity: entity, folder: data_room1)
end

# ── Deal 1 investors ──────────────────────────────────────────────────────────
inv1a = available_investors[0]
inv1b = available_investors[1]
inv1c = available_investors[2]
inv1d = available_investors[3]

# Investor A — Active & progressing (lead investor, 3 steps done, docs present)
log "\n  Investor A — Active & Progressing"
di1a = create_investor(
  deal: deal1, entity: entity, investor: inv1a,
  status: "Active", amount: 10_000_000_00, tier: "Lead",
  lead: "Priya Sharma", source: "Warm Intro", tags: "strategic,lead",
  notes: "Anchor investor. Very engaged — attended all management presentations. " \
         "Key concern: board seat composition. Positive on the product roadmap. " \
         "Committed to term sheet by end of quarter."
)
complete_steps(di1a, deal1, ["Info Deck Sent", "NDA Executed", "Management Presentation"])
set_by_dates(di1a, deal1)
attach_doc(owner: di1a, name: "Horizon NDA Signed",       filename: "Mutual-Confidentiality-Agreement.docx", user: admin, entity: entity)
attach_doc(owner: di1a, name: "Horizon Term Sheet Draft", filename: "SPA.docx",                              user: admin, entity: entity)
attach_doc(owner: di1a, name: "Horizon Financial Model",  filename: "CashFlow.xlsx",                         user: admin, entity: entity)
# Attach a doc to the completed "Management Presentation" activity
mgmt_act1a = di1a.deal_activities.find_by(title: "Management Presentation")
attach_doc(owner: mgmt_act1a, name: "Mgmt Pres Deck", filename: "Offer_1_SPA.pdf", user: admin, entity: entity) if mgmt_act1a

# Investor B — Active & stagnant, overdue activities
log "\n  Investor B — Stagnant & Overdue"
di1b = create_investor(
  deal: deal1, entity: entity, investor: inv1b,
  status: "Active", amount: 5_000_000_00, tier: "Follow-on",
  lead: "Karan Mehta", source: "Cold Outreach", tags: "at-risk",
  notes: "Has not responded to last two emails. Last contact was 3 weeks ago after " \
         "the management presentation. Possible concerns about burn rate. " \
         "Need to schedule follow-up call urgently."
)
complete_steps(di1b, deal1, ["Info Deck Sent"])
set_by_dates(di1b, deal1)
make_overdue(di1b, "NDA Executed",           14)
make_overdue(di1b, "Management Presentation", 5)
backdate_stagnant(di1b, 20)
attach_doc(owner: di1b, name: "Vertex NDA Signed", filename: "Mutual-Confidentiality-Agreement.docx", user: admin, entity: entity)

# Investor C — Pending, upcoming due dates (triggers reminder logic)
log "\n  Investor C — Upcoming Due Dates"
di1c = create_investor(
  deal: deal1, entity: entity, investor: inv1c,
  status: "Pending", amount: 8_000_000_00, tier: "Co-investor",
  lead: "Ananya Rao", source: "LP Network", tags: "family-office,co-invest",
  notes: "In diligence phase. Scheduled a call with their IC next week. " \
         "Expects draft SHA by end of month. Supportive on valuation. " \
         "Wants to understand exit mechanics before committing."
)
complete_steps(di1c, deal1, ["Info Deck Sent", "NDA Executed"])
set_by_dates(di1c, deal1)
make_upcoming(di1c, "Financial Due Diligence", 2)
make_upcoming(di1c, "Term Sheet Issued",        6)
attach_doc(owner: di1c, name: "Bansal NDA Executed",     filename: "Mutual-Confidentiality-Agreement.docx", user: admin, entity: entity)
attach_doc(owner: di1c, name: "Bansal Diligence Report", filename: "CRISIL Report.xlsx",                    user: admin, entity: entity)

# Investor D — Declined (excluded from pipeline)
log "\n  Investor D — Declined"
di1d = create_investor(
  deal: deal1, entity: entity, investor: inv1d,
  status: "Declined", amount: 2_000_000_00, tier: "Minority",
  lead: "Priya Sharma", source: "Conference", tags: "declined",
  notes: "Passed due to allocation constraints for the quarter. May revisit in Series C."
)
complete_steps(di1d, deal1, ["Info Deck Sent"])
set_by_dates(di1d, deal1)

# ============================================================================
# DEAL 2 — Seed Round
# ============================================================================
log "\n═══ Deal 2: Seed Round — NovaTech Ventures ═══"

deal2 = Deal.new(
  entity:       entity,
  name:         "Seed Round — NovaTech Ventures (Demo)",
  status:       "Open",
  amount_cents: 5_000_000_00,
  currency:     "USD",
  start_date:   45.days.ago.to_date,
  end_date:     90.days.from_now.to_date,
  tags:         "DeepTech,AI,Seed",
  units:        "shares"
)
CreateDeal.wtf?(deal: deal2)
raise "CreateDeal failed: #{deal2.errors.full_messages.join(', ')}" unless deal2.persisted?
log "Created Deal##{deal2.id}: #{deal2.name}"

create_activity_templates(deal2, entity)

# ── Deal 2 data room ──────────────────────────────────────────────────────────
data_room2 = deal2.deal_documents_folder
[
  ["Pitch Deck",          "Offer_1_SPA.pdf"  ],
  ["Financial Projections", "CashFlow.xlsx"  ],
  ["SAFE Agreement Draft",  "SPA.docx"       ],
].each do |(name, file)|
  attach_doc(owner: deal2, name: name, filename: file, user: admin, entity: entity, folder: data_room2)
end

# ── Deal 2 investors ──────────────────────────────────────────────────────────
inv2a = available_investors[4]
inv2b = available_investors[5]
inv2c = available_investors[6]

# Investor E — Active & early stage (2 steps done)
log "\n  Investor E — Active & Progressing"
di2a = create_investor(
  deal: deal2, entity: entity, investor: inv2a,
  status: "Active", amount: 2_000_000_00, tier: "Lead",
  lead: "Vikram Nair", source: "Angel Network", tags: "strategic,deep-tech",
  notes: "Very bullish on the AI angle. Has invested in 3 similar seed rounds this year. " \
         "Wants co-investor rights on Series A. Quick decision-maker — expects term sheet in 2 weeks."
)
complete_steps(di2a, deal2, ["Info Deck Sent", "NDA Executed"])
set_by_dates(di2a, deal2)
attach_doc(owner: di2a, name: "NovaTech NDA Signed",  filename: "Mutual-Confidentiality-Agreement.docx", user: admin, entity: entity)
attach_doc(owner: di2a, name: "Investment Memo Draft", filename: "SPA.docx",                              user: admin, entity: entity)

# Investor F — Active with overdue NDA step
log "\n  Investor F — Overdue NDA"
di2b = create_investor(
  deal: deal2, entity: entity, investor: inv2b,
  status: "Active", amount: 1_500_000_00, tier: "Co-investor",
  lead: "Siddharth Rao", source: "Referral", tags: "fintech-focused",
  notes: "Interested but slow on legal. NDA was supposed to be signed last week. " \
         "Their counsel requested minor changes to confidentiality clause."
)
complete_steps(di2b, deal2, ["Info Deck Sent"])
set_by_dates(di2b, deal2)
make_overdue(di2b, "NDA Executed", 7)
attach_doc(owner: di2b, name: "Redlined NDA", filename: "Mutual-Confidentiality-Agreement.docx", user: admin, entity: entity)

# Investor G — Declined
log "\n  Investor G — Declined"
di2c = create_investor(
  deal: deal2, entity: entity, investor: inv2c,
  status: "Declined", amount: 500_000_00, tier: "Minority",
  lead: "Vikram Nair", source: "Cold Outreach", tags: "declined",
  notes: "Ticket size too small for their fund mandate. Suggested two other funds to approach."
)
complete_steps(di2c, deal2, ["Info Deck Sent"])
set_by_dates(di2c, deal2)

# ============================================================================
# Summary
# ============================================================================
log "\n════════════════════════════════════════════"
log "Demo deals seeded for entity #{ENTITY_ID}"
log "════════════════════════════════════════════"

[deal1, deal2].each do |deal|
  deal.reload
  log "\n#{deal.name} (Deal##{deal.id})"
  log "  Status: #{deal.status}  |  Data room: #{deal.deal_documents_folder.documents.count} docs"
  deal.deal_investors.includes(:deal_activities).each do |di|
    log "  [#{di.status.ljust(9)}] #{di.investor_name.ljust(42)} " \
        "| #{di.deal_activities.count} activities " \
        "| #{Document.where(owner_type: 'DealInvestor', owner_id: di.id).count} docs" \
        "| stagnant=#{di.stagnant?}"
  end
end

# Resolve agent
agent = SupportAgent.find_by(entity_id: ENTITY_ID, agent_type: "DealManagementAgent")
if agent
  log "\n── Agent ready ─────────────────────────────────────────────────────────"
  log "SupportAgent##{agent.id} DealManagementAgent (enabled=#{agent.enabled})"
  log ""
  log "Run against Deal 1:"
  log "  DealManagementAgent.wtf?(support_agent_id: #{agent.id}, target: Deal.find(#{deal1.id}))"
  log ""
  log "Run against Deal 2:"
  log "  DealManagementAgent.wtf?(support_agent_id: #{agent.id}, target: Deal.find(#{deal2.id}))"
else
  log "\nWARN: DealManagementAgent not found for entity #{ENTITY_ID}."
  log "Run first:  rake 'support_agents:setup[#{ENTITY_ID}]'"
end

end # Chewy.strategy(:bypass)
