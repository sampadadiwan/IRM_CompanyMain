# US GTM Feature Specs

This folder contains feature specifications for every capability required to support the CapHive US go-to-market. Each file covers one feature area with: use cases, user personas, current platform state, build approach, and detailed requirements.

## Build Approach Legend
- **Enhance** — feature exists; needs US-specific additions to existing models/controllers
- **Build** — net-new feature; no meaningful existing foundation
- **Integrate** — requires a third-party API/provider to be wired in

## Feature Index

| File | Feature | Approach | Phase |
|------|---------|----------|-------|
| [us_fund_legal_structure.md](us_fund_legal_structure.md) | US legal structure, vehicle type, exemption type as FormCustomField on `Fund`; Entity unchanged; no new FK columns — feeder→master and feeder commitment tracking already modelled via existing `master_fund_id` / `feeder_fund_id` associations | Enhance | P0 |
| [us_investor_taxonomy.md](us_investor_taxonomy.md) | US investor types via existing `Investor.category` + FormCustomField KYC templates; only real model change is encrypted TIN column | Enhance | P0 |
| [investor_qualification_engine.md](investor_qualification_engine.md) | Accredited investor, QP, QC, ERISA, 3(c)(1) rules engine | Build | P0 |
| [us_tax_forms.md](us_tax_forms.md) | W-9 / W-8 / FATCA collection — using existing FormCustomField on InvestorKyc | Enhance | P0 |
| [bank_instruction_controls.md](bank_instruction_controls.md) | Bank verification, fraud controls, payment instruction lifecycle | Build + Integrate | P0 |
| [us_kyc_kyb.md](us_kyc_kyb.md) | US KYC/KYB — identity, entity, sanctions, AML (Persona, Middesk, ComplyAdvantage) | Enhance + Integrate | P0 |
| [us_esign_subscription.md](us_esign_subscription.md) | US e-sign providers (DocuSign, Dropbox Sign) + subscription packet engine | Enhance + Integrate | P0 |
| [closing_room.md](closing_room.md) | Extend KycOnboardingAgent with US steps + enhance Onboarding Report — not a new model | Enhance | P1 |
| [capital_events_us.md](capital_events_us.md) | Unfunded commitment field, dual approval, fund bank account, recallable distributions, default interest | Enhance | P1 |
| [tax_center.md](tax_center.md) | K-1 delivery, CPA delegation, tax year folders | Build | P1 |
| [fund_admin_exchange.md](fund_admin_exchange.md) | Structured data exchange with US fund administrators | Build | P1 |
| [side_letter_obligations.md](side_letter_obligations.md) | Side letter upload, LP obligation matrix, MFN tracking | Build | P1/P2 |
| [compliance_evidence_binder.md](compliance_evidence_binder.md) | Per-investor compliance summary and audit-ready evidence package | Build | P1/P2 |
| [ai_subscription_review.md](ai_subscription_review.md) | AI-powered subscription document exception detection | Build | P2 |
| [ai_document_intelligence.md](ai_document_intelligence.md) | LPA / side letter AI term extraction, source-cited answers | Build | P2 |
