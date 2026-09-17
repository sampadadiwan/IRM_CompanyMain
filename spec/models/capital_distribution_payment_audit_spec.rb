require 'rails_helper'

# json_fields["ae_audit"] is a fee trail rebuilt from the commitment's account_entries on every
# save, and on a long history it runs to hundreds of KB. audits.audited_changes is a MySQL TEXT
# capped at 64KB, so auditing it made saves fail outright with "Data too long for column
# 'audited_changes'". It is now stripped from the audit payload — but the rest of json_fields
# (custom fields, the per-fee amounts) is real user data and must still be versioned.
RSpec.describe CapitalDistributionPayment, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:entity) { FactoryBot.create(:entity, entity_type: "Company") }
  let(:fund) { FactoryBot.create(:fund, entity: entity, currency: "INR") }
  let(:investor_entity) { FactoryBot.create(:entity, entity_type: "Investor") }
  let(:investor) do
    FactoryBot.create(:investor, entity: entity, investor_entity: investor_entity,
                                 investor_name: investor_entity.name)
  end
  let(:capital_commitment) do
    FactoryBot.create(:capital_commitment, fund: fund, entity: entity, investor: investor,
                                           unit_type: "Series A", folio_id: "FOLIO-1",
                                           folio_currency: "INR", fund_close: "First Close",
                                           commitment_date: Date.new(2026, 1, 1))
  end
  let(:capital_distribution) do
    FactoryBot.create(:capital_distribution, fund: fund, entity: entity,
                                             title: "Dist 1", distribution_date: Date.new(2026, 6, 1),
                                             unit_prices: nil)
  end

  # A trail big enough to have overflowed the old column, so the specs below prove the fix on
  # the payload that actually broke rather than on a token one.
  let(:big_ae_audit) { [Array.new(5000) { |i| ["Management Fee", "2026-01-01", i * 100, "Expense"] }] }

  def build_payment(json_fields:)
    described_class.new(fund: fund, entity: entity, capital_distribution: capital_distribution,
                        investor: investor, capital_commitment: capital_commitment,
                        folio_id: capital_commitment.folio_id, investor_name: investor.investor_name,
                        payment_date: Date.new(2026, 6, 1), json_fields: json_fields)
  end

  def latest_audit(payment) = payment.audits.reload.last

  describe "auditing json_fields" do
    it "keeps ae_audit out of the create audit but versions the rest" do
      payment = build_payment(json_fields: { "ae_audit" => big_ae_audit, "management_fee" => "₹1,000" })
      payment.save!

      audited = latest_audit(payment)

      expect(audited.action).to eq("create")
      expect(audited.audited_changes["json_fields"]).to eq("management_fee" => "₹1,000")
      expect(audited.read_attribute_before_type_cast("audited_changes").to_s.bytesize).to be < 64.kilobytes
    end

    it "keeps ae_audit out of the update audit while still recording the other json_fields" do
      payment = build_payment(json_fields: { "ae_audit" => [], "management_fee" => "₹1,000" })
      payment.save!

      payment.json_fields = { "ae_audit" => big_ae_audit, "management_fee" => "₹2,000" }
      payment.save!

      audited = latest_audit(payment)

      expect(audited.action).to eq("update")
      expect(audited.audited_changes["json_fields"]).to eq([{ "management_fee" => "₹1,000" },
                                                            { "management_fee" => "₹2,000" }])
      expect(audited.read_attribute_before_type_cast("audited_changes").to_s.bytesize).to be < 64.kilobytes
    end

    it "still records a dated audit when a recompute only rewrites ae_audit" do
      payment = build_payment(json_fields: { "ae_audit" => [], "management_fee" => "₹1,000" })
      payment.save!
      before_count = payment.audits.count

      travel_to(Time.zone.parse("2026-06-02 10:00")) do
        payment.json_fields = { "ae_audit" => big_ae_audit, "management_fee" => "₹1,000" }
        payment.save!
      end

      expect(payment.audits.reload.count).to eq(before_count + 1)

      audited = latest_audit(payment)

      expect(audited.action).to eq("update")
      expect(audited.audited_changes.keys).to eq(["updated_at"])
      expect(audited.audited_changes["updated_at"].last.to_time).to eq(Time.zone.parse("2026-06-02 10:00"))
      expect(audited.read_attribute_before_type_cast("audited_changes").to_s.bytesize).to be < 64.kilobytes
    end

    it "does not record an identical before and after for json_fields" do
      payment = build_payment(json_fields: { "ae_audit" => [], "management_fee" => "₹1,000" })
      payment.save!

      payment.json_fields = { "ae_audit" => big_ae_audit, "management_fee" => "₹1,000" }
      payment.save!

      expect(latest_audit(payment).audited_changes).not_to have_key("json_fields")
    end

    it "keeps ae_audit out of the destroy audit" do
      payment = build_payment(json_fields: { "ae_audit" => big_ae_audit, "management_fee" => "₹1,000" })
      payment.save!

      payment.destroy

      audited = latest_audit(payment)

      expect(audited.action).to eq("destroy")
      expect(audited.audited_changes["json_fields"]).to eq("management_fee" => "₹1,000")
      expect(audited.read_attribute_before_type_cast("audited_changes").to_s.bytesize).to be < 64.kilobytes
    end

    it "leaves the record's own ae_audit untouched" do
      payment = build_payment(json_fields: { "ae_audit" => big_ae_audit, "management_fee" => "₹1,000" })
      payment.save!

      expect(payment.reload.json_fields["ae_audit"]).to eq(big_ae_audit)
    end

    it "still audits changes to columns other than json_fields" do
      payment = build_payment(json_fields: { "ae_audit" => big_ae_audit })
      payment.save!

      payment.update!(investor_name: "Renamed Investor")

      expect(latest_audit(payment).audited_changes).to include("investor_name")
    end
  end
end
