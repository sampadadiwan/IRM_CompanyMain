# The evergreen folio page (GP and the folio's own investor): holding, transactions, requests and
# documents of one folio. Existing commitment pages redirect here for evergreen funds.
# Worked examples H35, H67, H68, E48, E206 — openspec/changes/open-ended-funds/design.md#worked-examples
module Evergreen
  class FoliosController < BaseController
    before_action :require_evergreen!

    def show
      @folio = @fund.capital_commitments.find(params[:id])
      authorize @folio, :show?
      @row = EvergreenUnitRegister.new(@fund, folio_ids: [@folio.id]).rows.first
      @orders = DealingOrder.where(capital_commitment_id: @folio.id).includes(:dealing_date, :fund, :entered_by, :dealing_fills).order(received_at: :desc)
      # Latest approved NAV per class: the Amount / Units estimate for the side the investor didn't ask in (as on the order book)
      @navs = @orders.map(&:unit_type).uniq.index_with { |ut| FundNav.latest_approved(@fund, ut, Time.zone.today) }
      load_unit_history
      # Documents tab, newest first. GP users who can edit the folio also see generated documents still
      # waiting for approval (statements), badged on the tab; everyone else sees approved ones only
      # (evergreen-folio-soa ⑥: H5 badge for the GP, E17 investor never sees unapproved)
      docs = Document.where(owner: @folio)
      docs = docs.exclude_generated_unapproved unless policy(@folio).update?
      @documents = docs.order(created_at: :desc)
      # Investing entity picker: the investor's approved KYCs, offered only while the folio has none (③)
      @approved_kycs = @folio.investor_kyc_id || !policy(@folio).update? ? InvestorKyc.none : approved_kycs
    end

    # Link an approved KYC to a folio that has none (evergreen-folio-soa ③). Link-only: a linked folio's
    # investing entity never changes. H8 links; X12 another investor's KYC; X13 already linked; X14 read-only user
    def link_kyc
      @folio = @fund.capital_commitments.find(params[:id])
      authorize @folio, :update?
      kyc_id = params[:investor_kyc_id].to_i
      alert = if @folio.investor_kyc_id
                # X13
                "This #{EvergreenLabels.lower(EvergreenLabels.t(:capital_commitment, fund: @fund))} already has an investing entity"
              elsif approved_kycs.where(id: kyc_id).none?
                # X12 (also a blank pick)
                "Choose one of #{@folio.investor.investor_name}'s approved KYCs"
              end
      return redirect_to(evergreen_folio_path(@fund, @folio), alert:) if alert

      # update! (not update_column) so the investor KYC's commitment counters stay right
      @folio.update!(investor_kyc_id: kyc_id)
      redirect_to evergreen_folio_path(@fund, @folio), notice: "Investing entity linked"
    end

    private

    # The folio investor's approved KYCs (the only ones a folio may be linked to)
    def approved_kycs
      InvestorKyc.where(entity_id: @folio.entity_id, investor_id: @folio.investor_id, verified: true).order(:full_name)
    end

    # Every unit movement of the folio, oldest first, with a running balance (H68, E206). Movements
    # made by a dealing fill link to their order; the rest (opening units, transfers) show their reason.
    def load_unit_history
      units = FundUnit.where(capital_commitment_id: @folio.id).order(:issue_date, :id)
                      .select(:id, :issue_date, :quantity, :price_cents, :premium_cents, :reason)
      fills = DealingFill.where(fund_unit_id: units.map(&:id)).includes(:dealing_date, :dealing_order).index_by(&:fund_unit_id)
      balance = 0.to_d
      @unit_history = units.map do |u|
        balance += u.quantity.to_d
        { unit: u, fill: fills[u.id], price_cents: u.price_cents.to_d + u.premium_cents.to_d, balance: }
      end
    end
  end
end
