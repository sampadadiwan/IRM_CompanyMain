class DealInvestorDestroy < DealInvestorAction
  step :destroy
  step :remove_access_to_deal

  def destroy(_ctx, deal_investor:, **)
    deal_investor.destroy
  end

  def remove_access_to_deal(_ctx, deal_investor:, **)
    AccessRight.where(owner: deal_investor.deal, entity_id: deal_investor.entity_id, access_to_investor_id: deal_investor.investor_id).destroy_all
  end
end
