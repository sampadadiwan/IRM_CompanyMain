"""Adds domain, tier and plain-English blurbs to data.json."""
import json, sys

src, out = sys.argv[1], sys.argv[2]
d = json.load(open(src))
T = d["tables"]

DOMAINS = [
    ("funds", "Funds & capital", "Funds, LP commitments, calls, remittances, distributions and units."),
    ("accounting", "Accounting & calculations", "The ledger, the formulas that write it, and the ratios computed from it."),
    ("evergreen", "Open-ended funds", "Dealing dates, subscriptions, redemptions and NAV per share class."),
    ("investors", "Investors & onboarding", "LPs, portfolio companies and every other stakeholder, with KYC and access."),
    ("portfolio", "Portfolio & valuations", "Holdings, cost lots, cash flows, valuations, KPIs and cap tables."),
    ("deals", "Deals & secondaries", "Pipeline, co-invest opportunities and secondary transactions."),
    ("documents", "Documents & reporting", "Documents, e-signature, generated reports and dashboards."),
    ("extend", "Extensibility", "Custom fields, validation rules, tags, saved views and imports."),
    ("workflow", "Workflow & collaboration", "Tasks, approvals, workflows, reminders and notes."),
    ("ai", "AI & agents", "Assistants, agents, AI checks and AI-drafted reports."),
    ("platform", "Platform", "Tenancy, users, roles, permissions, audit and integrations."),
]

PACK = {
    "funds/capital_calls": "funds", "funds/capital_commitments": "funds", "funds/capital_distributions": "funds",
    "funds/capital_distribution_payments": "funds", "funds/capital_remittances": "funds", "funds/side_letters": "funds",
    "funds/fund_reports": "documents", "funds/funds": "funds", "funds/derivatives": "portfolio",
    "funds/evergreen": "evergreen", "funds/financial_statements": "accounting", "funds/market_data": "accounting",
    "funds/portfolios": "portfolio", "funds/investment_opportunities": "deals",
    "startups/deals": "deals", "startups/investments": "portfolio", "startups/kpis": "portfolio",
    "secondaries/interests": "deals", "secondaries/offers": "deals", "secondaries/secondary_sales": "deals",
    "core/documents": "documents", "core/folders": "documents", "core/investors": "investors",
    "core/investor_kycs": "investors", "core/investor_accesses": "investors", "core/nda_configs": "investors",
    "core/valuations": "portfolio", "core/tasks": "workflow", "core/workflow_templates": "workflow",
    "core/reminders": "workflow", "core/notes": "workflow", "core/nudges": "workflow", "core/notifications": "workflow",
    "core/validation_rules": "extend", "core/fees": "funds",
    "misc/form_types": "extend", "misc/form_custom_fields": "extend", "misc/import_uploads": "extend",
    "misc/approvals": "workflow", "misc/kanbans": "deals", "misc/investor_notices": "investors",
    "misc/incoming_emails": "workflow", "misc/payments": "platform", "misc/blogs": "platform",
}
OVERRIDE = {
    "account_entries": "accounting", "account_entry_report_insights": "accounting", "fund_formulas": "accounting",
    "fund_formula_operations": "accounting", "ratio_formulas": "accounting", "fund_ratios": "accounting",
    "fund_ratio_runs": "accounting", "fund_ratio_run_templates": "accounting", "tie_out_figures": "accounting",
    "exchange_rates": "accounting", "market_data_settings": "accounting",
    "portfolio_report_drafts": "documents", "portfolio_report_extracts": "documents", "portfolio_report_sections": "documents",
    "portfolio_report_templates": "documents", "portfolio_reports": "documents", "tear_sheet_presentations": "documents",
    "reports": "documents", "report_schedules": "documents", "dashboard_widgets": "documents",
    "custom_grid_views": "extend", "grid_view_preferences": "extend", "tags": "extend", "taggings": "extend",
    "custom_notifications": "extend", "funding_rounds": "portfolio", "key_biz_metrics": "portfolio",
    "kyc_data": "investors", "video_kycs": "investors", "deal_docs": "deals", "ci_profiles": "deals",
    "ticker_feeds": "accounting", "ai_kpi_shadow_runs": "ai", "template_authoring_runs": "ai", "template_brackets": "documents",
    "notifications": "workflow", "events": "workflow", "investment_criteria_templates": "ai",
}
for t in [k for k in T if k.startswith("allocation_")]:
    OVERRIDE[t] = "accounting"

INTERNAL_PREFIX = ("active_storage_", "action_", "blazer_", "solid_", "noticed_", "ruby_llm_", "oauth_", "mobile_")
INTERNAL = {"friendly_id_slugs", "active_admin_comments", "exception_tracks", "devise_api_tokens", "otp_deliveries",
            "phone_change_requests", "email_bounce_events", "sync_records", "website_leads", "blogs", "users_roles",
            "admin_users", "viewed_bies", "favorites", "quick_links", "quick_link_steps", "guide_search_synonyms",
            "faq_entries", "faq_threads", "support_client_mappings", "support_console_queries", "customer_support_escalations",
            "agent_chat_message_feedbacks", "user_alerts", "nudges", "events", "notifications", "messages", "chats",
            "zoho_sign_connections", "api_tokens", "payments", "template_brackets", "template_authoring_runs",
            "ai_kpi_shadow_runs", "grid_view_preferences", "fund_formula_operations", "evergreen_notification_logs",
            "obligation_reminders", "nda_expiry_reminders", "esign_logs", "deal_ingest_addresses", "agent_ingested_emails",
            "ci_profiles", "deal_docs", "key_biz_metrics", "funding_rounds", "ticker_feeds", "video_kycs", "kyc_data"}

CORE = {"entities", "funds", "capital_commitments", "capital_calls", "capital_remittances", "capital_remittance_payments",
        "capital_distributions", "capital_distribution_payments", "account_entries", "fund_formulas", "fund_ratios",
        "ratio_formulas", "fund_units", "fund_unit_settings", "investors", "investor_kycs", "portfolio_investments",
        "aggregate_portfolio_investments", "investment_instruments", "valuations", "kpi_reports", "kpis",
        "investor_kpi_mappings", "documents", "form_types", "form_custom_fields", "fund_navs", "exchange_rates",
        "call_fees", "portfolio_cashflows", "deals", "allocation_runs"}

BLURB = {
    "entities": "Your organisation. Every row in every business table carries an entity_id, so each firm's data is isolated at the row level.",
    "funds": "A fund, feeder or SPV. Holds currency, unit classes, master/feeder link, rolled-up committed, called, collected and distributed totals.",
    "capital_commitments": "An LP's commitment to a fund — the folio. Holds committed, called, collected and distributed amounts in the fund currency and in the folio's own currency.",
    "capital_calls": "A drawdown notice. Called by percentage of commitment, by amount, or by upload; can bundle fees and an investment amount.",
    "call_fees": "Fees bundled into a capital call: part-of-capital, other fees, or investment amount. Each is computed per folio from ledger entries in a date window, or by formula.",
    "capital_remittances": "One LP's share of a capital call: what is due, what has been collected, fees, arrears, units issued.",
    "capital_remittance_payments": "Individual payments received against a remittance, in fund and folio currency, with proof of payment.",
    "capital_distributions": "A distribution event: gross amount, carry, income, return of cost, reinvestment and fees.",
    "capital_distribution_payments": "One LP's share of a distribution, broken into income, cost of investment, reinvestment, tax and fees; gross and net payable.",
    "distribution_fees": "Deductions applied to a distribution per LP, computed from ledger entries or a formula.",
    "commitment_adjustments": "Increases, decreases and transfers of a commitment, with before/after values and an as-of date.",
    "fund_units": "The unit ledger: units issued on calls, redeemed on distributions and moved on transfers, each tied to the transaction that caused it.",
    "fund_unit_settings": "A unit class (share class): management fee, setup fee, carry %, GP units, ISIN.",
    "fund_unit_transfers": "Transfers of units and commitment between two folios, with ratio, price and premium.",
    "side_letters": "An executed side letter on a commitment, linked to its document.",
    "side_letter_obligations": "Each obligation extracted from a side letter: type, trigger, recurrence, owner, MFN relevance, review status.",
    "account_entries": "The fund ledger. Every income, expense, fee, allocation and computed figure, at fund, folio or portfolio level, with the formula that produced it and an explanation of how.",
    "fund_formulas": "The formulas that run a fund's accounting. Each has a rule type, a sequence and an expression; the allocation engine runs them in order and writes account entries.",
    "allocation_runs": "One execution of a fund's formulas for a period: who ran it, which options, status, and whether it is locked.",
    "allocation_run_reports": "The checks and findings from an allocation run, including pre- and post-run check results.",
    "ratio_formulas": "Adjustments to a standard ratio: add or subtract named ledger amounts on the value, capital or cash-flow side.",
    "fund_ratios": "A computed performance metric (XIRR, DPI, TVPI, MOIC…) for a fund, folio or portfolio company as of a date. Stores the cash flows it was computed from.",
    "fund_ratio_runs": "A batch run of ratio computation across funds or companies.",
    "exchange_rates": "FX rates by date, used to keep folio, instrument and tracking-currency amounts in step.",
    "financial_statements": "A generated Balance Sheet, P&L or statement of partners' capital for a period, lockable once checked.",
    "financial_statement_accounts": "The chart of accounts a fund's statements are built from.",
    "financial_statement_mapping_rules": "Maps ledger entries (by name or entry type) to statement accounts.",
    "tie_out_figures": "External figures (e.g. from the administrator) that the ledger is checked against.",
    "fund_navs": "A NAV for one share class on one date: assets, liabilities, fees payable and accrued, units, NAV per unit, high-water mark. Draft, then approved.",
    "evergreen_class_terms": "Terms per share class: initial price, performance fee model and %, hurdle, crystallisation, lock-up, minimums.",
    "dealing_dates": "The dates on which an open-ended fund accepts subscriptions and redemptions.",
    "dealing_orders": "Subscription and redemption orders against a dealing date.",
    "dealing_fills": "How an order was filled at the approved NAV.",
    "investors": "Any stakeholder: LP, portfolio company, co-investor, advisor. A category tells them apart, so one table serves the whole relationship graph.",
    "investor_kycs": "KYC for an investing entity or individual: tax id, address, bank details, verification status, and as many custom questions as you configure.",
    "investor_accesses": "Who at an investor can log in and see what.",
    "aml_reports": "AML screening results against a KYC.",
    "portfolio_investments": "A single buy, sell or conversion of an instrument by a fund. Tracks quantity, cost, FMV, realised and unrealised gain, in fund and instrument currency.",
    "aggregate_portfolio_investments": "A fund's position in one instrument of one company: bought, sold, cost of remaining, FMV, gains — the roll-up of its portfolio investments.",
    "portfolio_attributions": "Which buy lots each sale drew from (FIFO or weighted average), with cost of sold and gain per lot.",
    "portfolio_cashflows": "Income and other cash from a holding: dividends, interest, fees.",
    "investment_instruments": "A security: equity, preference, debt, SAFE, fund units. Currency, ISIN/ticker, pricing method.",
    "valuations": "A valuation of an instrument or company on a date: total and per-share value. Drives FMV across every fund that holds it.",
    "stock_conversions": "Conversion of one instrument into another (e.g. preference to equity) with quantities on both sides.",
    "investments": "A company's cap-table entry: who holds what, in which round.",
    "shareholder_positions": "Shareholding positions in a portfolio company, with fully diluted %.",
    "kpi_reports": "A portfolio company's KPI submission for a period (actuals, budget, forecast), with approval status.",
    "kpis": "One metric value in a KPI report — revenue, ARR, headcount — with RAG status and FX conversion.",
    "investor_kpi_mappings": "How a company's reported KPI names map to your standard names, plus thresholds, RAG rules, compute formula and FX method.",
    "derivative_contracts": "Hedges and other derivatives: type, underlying, strike, notional, expiry, what they hedge.",
    "deals": "A deal in the pipeline with stages, documents and a data room.",
    "deal_investors": "A participant in a deal: commitment, status, tier, notes, AI score.",
    "investment_opportunities": "A co-invest or fund opportunity offered to LPs.",
    "expression_of_interests": "An LP's indication of interest in an opportunity.",
    "secondary_sales": "A secondary sale process with offers and interests.",
    "documents": "Any file: generated notices, statements, KYC uploads, agreements. Attaches to any record, carries e-sign status and access rules.",
    "folders": "The folder tree documents live in.",
    "e_signatures": "Signers and status for a document sent for e-signature.",
    "form_types": "A container of custom fields for one kind of record (e.g. Investor), optionally tagged so one record kind can have several.",
    "form_custom_fields": "One custom field: name, type, options, step, validation rules, conditional visibility, or a calculation.",
    "validation_rules": "Configurable validation rules that run on save or on demand.",
    "import_uploads": "Every spreadsheet import. Rows created or changed by an import keep its id, so any record can be traced back to the file it came from.",
    "reports": "Saved Report Builder reports.",
    "audits": "Field-level change history: who changed what, when, from what to what.",
    "users": "Logins: employees, investors, advisors.",
    "roles": "Roles assigned to users.",
    "access_rights": "Fine-grained grants: which user or investor category can see which fund, deal or document.",
    "tasks": "Tasks with owners, due dates and recurrence, attachable to any record.",
    "approvals": "An approval request sent to a set of investors or users.",
    "workflow_templates": "Reusable multi-step workflows with actors and auto-assignment.",
}

# Market-specific columns (India KYC, e-sign and depository integrations) are left out of the
# explorer: they are empty for funds outside that market. Two general-purpose columns keep
# India-era names in the database; they are shown under neutral names, and the page footnote
# gives the physical names so the explorer still matches a database copy.
REGION_TABLES = {"stamp_papers"}
REGION_COLUMNS = {"pan_verified", "pan_verification_response", "pan_verification_status", "pan_verification",
                  "pan_card_data", "demat", "ckyc_kra_enabled", "stamp_paper_tags", "disable_pan_kyc",
                  "digio_client_id", "digio_client_secret", "digio_cutover_date"}
REGION_DEFAULTS = {"SEBI", "Digio"}
ALIAS = {"PAN": "tax_id", "pan": "tax_id", "ifsc_code": "bank_routing_code"}
# Swagger examples recorded from an India-based demo, restated for the page only (swagger.yaml is unchanged).
EXAMPLES = {
    ("AccountEntry", "fund_currency"): "USD", ("AccountEntry", "folio_currency"): "EUR",
    ("PortfolioInvestment", "instrument_currency"): "USD", ("Valuation", "currency"): "USD",
    ("ExchangeRate", "to"): "EUR", ("Fund", "category"): "Closed-ended",
    ("FundUnit", "reason"): "Issuing units for net collected amount $500,000.00",
    ("CapitalRemittance", "investing_entity"): "John Doe Family Trust",
    ("Document", "name"): "Bank statement", ("Document", "owner_tag"): "Bank statement",
    ("CapitalCommitment", "tax_id"): "12-3456789",
}


def neutralise(tables, schemas):
    for name in REGION_TABLES:
        tables.pop(name, None)
    for t in tables.values():
        t["columns"] = [c for c in t["columns"] if c["name"] not in REGION_COLUMNS]
        for c in t["columns"]:
            c["name"] = ALIAS.get(c["name"], c["name"])
            if c.get("default") in REGION_DEFAULTS:
                del c["default"]
        t["indexes"] = [i for i in t["indexes"] if not REGION_COLUMNS & set(i["columns"])]
        for i in t["indexes"]:
            i["columns"] = [ALIAS.get(x, x) for x in i["columns"]]
        t["assocs"] = [a for a in t.get("assocs", []) if a.get("table") not in REGION_TABLES]
    for props in schemas.values():
        for k in [k for k in props if k in REGION_COLUMNS]:
            del props[k]
        for k in [k for k in props if k in ALIAS]:
            props[ALIAS[k]] = props.pop(k)
        for v in props.values():
            if v.get("example") == "INR":
                v["example"] = "USD"
    for (schema, prop), value in EXAMPLES.items():
        if prop in schemas.get(schema, {}):
            schemas[schema][prop]["example"] = value


neutralise(T, d["api"]["schemas"])

dom_names = {k: n for k, n, _ in DOMAINS}
for name, t in T.items():
    dom = OVERRIDE.get(name) or PACK.get(t.get("pack")) or ("ai" if (t.get("pack") or "").startswith("ai/") else "platform")
    t["domain"] = dom
    if name in CORE:
        t["tier"] = "core"
    elif name in INTERNAL or name.startswith(INTERNAL_PREFIX):
        t["tier"] = "internal"
    else:
        t["tier"] = "supporting"
    if name in BLURB:
        t["blurb"] = BLURB[name]
    t.pop("file", None)
    t.pop("pack", None)

d["domains"] = [{"id": k, "name": n, "desc": ds} for k, n, ds in DOMAINS]
json.dump(d, open(out, "w"), separators=(",", ":"))
from collections import Counter
print(Counter((t["domain"], t["tier"]) for t in T.values()))
