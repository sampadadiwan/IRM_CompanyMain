class AddDealInvestorStatusToDeals < ActiveRecord::Migration[8.1]
  def up
    add_column :deals, :deal_investor_status, :json

    say_with_time "Backfilling deal investor statuses from json_fields" do
      Deal.reset_column_information

      Deal.unscoped.find_each do |deal|
        next unless deal.json_fields.is_a?(Hash)

        legacy_statuses = deal.json_fields["deal_investor_status"]
        next if legacy_statuses.blank?

        deal.update_columns(
          deal_investor_status: legacy_statuses,
          json_fields: deal.json_fields.except("deal_investor_status")
        )
      end
    end
  end

  def down
    remove_column :deals, :deal_investor_status
  end
end