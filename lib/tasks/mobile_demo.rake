# frozen_string_literal: true

# Demo data for reviewing the LP mobile app (openspec/changes/lp-mobile-app, tasks 4.5).
#
#   RAILS_ENV=test TEST_ENV_NUMBER=mobiledemo bin/rails mobile:seed_demo
#
# Builds the design's shared setup — Arka Capital, Sharma Family Office's ₹5 Cr commitment to
# Arka Growth Fund I with Calls 1–3, a distribution, documents and alerts — plus a second fund
# manager, so every app screen has something real to show. Every name is fictional.
# Refuses to run in production; meant for a throwaway local database or staging.
namespace :mobile do
  desc "Seed fictional demo data for the LP mobile app review (never production)"
  task seed_demo: :environment do
    abort "mobile:seed_demo refuses to run in production" if Rails.env.production?

    require "factory_bot"
    FactoryBot.find_definitions if FactoryBot.factories.none?

    password = ENV.fetch("DEMO_PASSWORD", "password")
    cents = ->(rupees) { (rupees.to_d * 100).to_i }

    fm = Entity.find_by(name: "Arka Capital") ||
         FactoryBot.create(:entity, name: "Arka Capital", entity_type: "Investment Fund", enable_funds: true, currency: "INR")
    gp = fm.employees.first || FactoryBot.create(:user, entity: fm, email: "meera@arkacapital.example", first_name: "Meera", last_name: "Iyer", password:)
    lp_entity = Entity.find_by(name: "Sharma Family Office") ||
                FactoryBot.create(:entity, name: "Sharma Family Office", entity_type: "Investor")
    investor = Investor.find_by(entity_id: fm.id, investor_entity_id: lp_entity.id) ||
               FactoryBot.create(:investor, entity: fm, investor_entity: lp_entity, investor_name: lp_entity.name,
                                            primary_email: lp_entity.primary_email)
    rahul = User.find_by(email: "rahul@sharmafo.example") ||
            FactoryBot.create(:user, email: "rahul@sharmafo.example", first_name: "Rahul", last_name: "Sharma",
                                     entity: lp_entity, password:)
    InvestorAccess.find_or_create_by!(entity: fm, investor:, email: rahul.email) do |ia|
      ia.user = rahul
      ia.first_name = rahul.first_name
      ia.last_name = rahul.last_name
      ia.approved = true
    end
    rahul.reload

    make_fund = lambda do |manager, inv, name|
      fund = Fund.find_by(name:) || FactoryBot.create(:fund, name:, entity: manager, currency: "INR", unit_types: "A")
      AccessRight.find_or_create_by!(entity: manager, owner: fund, access_to_investor_id: inv.id) { |ar| ar.notify = false }
      fund
    end

    fund = make_fund.call(fm, investor, "Arka Growth Fund I")
    cc = CapitalCommitment.find_by(fund:, investor:) ||
         FactoryBot.create(:capital_commitment, fund:, entity: fm, investor:, unit_type: "A", folio_id: "SFO-1",
                                                folio_currency: "INR", folio_committed_amount_cents: cents.call(50_000_000))

    calls = [["Capital Call 1", 7_500_000, 7_500_000, Date.new(2026, 1, 10), "Paid"],
             ["Capital Call 2", 5_000_000, 5_000_000, Date.new(2026, 6, 17), "Paid"],
             ["Capital Call 3", 7_500_000, 0, Time.zone.today + 17.days, "Pending"]]
    remittances = calls.map do |name, amount, collected, due, status|
      call = CapitalCall.find_by(fund:, name:) ||
             FactoryBot.create(:capital_call, fund:, entity: fm, name:, call_basis: "Upload", due_date: due, call_date: due - 30.days)
      rem = CapitalRemittance.find_by(capital_call: call, capital_commitment: cc) ||
            FactoryBot.create(:capital_remittance, capital_call: call, fund:, entity: fm, investor:, capital_commitment: cc,
                                                   folio_id: cc.folio_id, folio_committed_amount_cents: cents.call(50_000_000),
                                                   committed_amount_cents: cents.call(50_000_000))
      rem.update_columns(call_amount_cents: cents.call(amount), collected_amount_cents: cents.call(collected), other_fee_cents: 0,
                         status:, verified: status == "Paid", payment_date: status == "Paid" ? due - 5.days : nil)
      rem
    end

    dist = CapitalDistribution.find_by(fund:, title: "Distribution 1") ||
           FactoryBot.create(:capital_distribution, fund:, entity: fm, title: "Distribution 1", distribution_date: Date.new(2026, 8, 15))
    payment = CapitalDistributionPayment.find_by(capital_distribution: dist, folio_id: cc.folio_id) ||
              FactoryBot.create(:capital_distribution_payment, fund:, entity: fm, capital_distribution: dist, investor:,
                                                               capital_commitment: cc, folio_id: cc.folio_id)
    payment.update_columns(capital_commitment_id: cc.id, investor_id: investor.id, payment_date: Date.new(2026, 8, 15),
                           net_payable_cents: cents.call(3_000_000), gross_payable_cents: cents.call(3_000_000), completed: true)

    # The website card's figures, pinned last (creating calls re-runs the counter caches)
    cc.update_columns(committed_amount_cents: cents.call(50_000_000), call_amount_cents: cents.call(20_000_000),
                      collected_amount_cents: cents.call(12_500_000), distribution_amount_cents: cents.call(3_000_000), other_fee_cents: 0)

    add_doc = lambda do |owner, name, generated: false|
      Document.find_by(owner:, name:) ||
        FactoryBot.create(:document, name:, entity: fm, owner:, folder: owner.document_folder, user: gp, approved: true).tap do |d|
          d.update_columns(from_template_id: d.id) if generated
        end
    end
    add_doc.call(remittances[2], "Capital Call 3 Notice", generated: true)
    add_doc.call(cc, "Q2 2026 Statement")
    add_doc.call(cc, "Q1 2026 Statement")
    add_doc.call(payment, "Distribution 1 Advice")
    side_letter = add_doc.call(cc, "Side Letter")
    side_letter.update_columns(sent_for_esign: true, provider_doc_id: "DID-DEMO-1", esign_status: "requested")
    unless ESignature.exists?(document: side_letter, user: rahul)
      esign = ESignature.create!(entity: fm, document: side_letter, user: rahul, email: rahul.email, position: 1, signature_type: "Electronic")
      esign.update_columns(status: "requested")
    end

    # A second fund manager, so Home shows grouping (E29)
    beta = Entity.find_by(name: "Beta Partners") ||
           FactoryBot.create(:entity, name: "Beta Partners", entity_type: "Investment Fund", enable_funds: true, currency: "INR")
    beta_investor = Investor.find_by(entity_id: beta.id, investor_entity_id: lp_entity.id) ||
                    FactoryBot.create(:investor, entity: beta, investor_entity: lp_entity, investor_name: lp_entity.name,
                                                 primary_email: lp_entity.primary_email)
    InvestorAccess.find_or_create_by!(entity: beta, investor: beta_investor, email: rahul.email) do |ia|
      ia.user = rahul
      ia.first_name = rahul.first_name
      ia.last_name = rahul.last_name
      ia.approved = true
    end
    beta_fund = make_fund.call(beta, beta_investor, "Beta Opportunities Fund")
    beta_cc = CapitalCommitment.find_by(fund: beta_fund, investor: beta_investor) ||
              FactoryBot.create(:capital_commitment, fund: beta_fund, entity: beta, investor: beta_investor, unit_type: "A",
                                                     folio_id: "SFO-B1", folio_currency: "INR", folio_committed_amount_cents: cents.call(20_000_000))
    beta_cc.update_columns(committed_amount_cents: cents.call(20_000_000), call_amount_cents: cents.call(12_000_000),
                           collected_amount_cents: cents.call(12_000_000), distribution_amount_cents: cents.call(4_500_000), other_fee_cents: 0)

    # Alerts: the capital call notice (unread), the side letter (unread), and an older read one
    notify = lambda do |notifier, record, message, read: false, ago: 0|
      event = notifier.create!(record:, params: { entity_id: fm.id, email_method: "notify_capital_remittance", msg: message })
      Noticed::Notification.create!(event:, recipient: rahul, type: "#{notifier.name}::Notification",
                                    read_at: read ? Time.current : nil, created_at: ago.days.ago)
    end
    if Noticed::Notification.where(recipient: rahul).none?
      notify.call(CapitalRemittanceNotifier, remittances[1], "Capital Call 2 received — thank you", read: true, ago: 120)
      notify.call(DocumentNotifier, side_letter, "Side Letter — please sign", ago: 1)
      notify.call(CapitalRemittanceNotifier, remittances[2], "Capital Call by Arka Capital : Capital Call 3")
    end

    puts "Demo data ready. Sign in as #{rahul.email} / #{password} (region India)."
  end
end
