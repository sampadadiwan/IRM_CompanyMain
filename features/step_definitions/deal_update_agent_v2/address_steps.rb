# frozen_string_literal: true

# Step definitions for Deal Update Agent v2 address management scenarios.
# Tests that addresses are per-deal (not per-user), default to deal ID,
# and are shared across all users with deal access.

# --- Assertions: Default Address ---

Then("the deal ingest address should be the deal ID") do
  expect(@ingest_address.address).to eq(@deal.id.to_s),
    "Expected address '#{@deal.id}' but got '#{@ingest_address.address}'"
end

# --- Assertions: Shared Address ---

Then("both users should see the same deal ingest address") do
  # In v2, there is exactly one address per deal — all users share it.
  addresses = DealIngestAddress.where(deal: @deal)
  expect(addresses.count).to eq(1),
    "Expected 1 address for the deal but found #{addresses.count}"
end
