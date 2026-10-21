# frozen_string_literal: true

# Steps for features/mobile/mobile_multi_site.feature (openspec/changes/lp-mobile-multi-site).
# Regions are stubbed by cross_region_steps.rb ("the regions are", "the current region is");
# the phone helpers come from mobile_api_steps.rb and the Arka setup from mobile_data_steps.rb.

# ── Setup ────────────────────────────────────────────────────────────────────

Given("{string} belongs to the regions {string}") do |email, csv|
  # update_column: the stored value is what User#switchable_region_codes reads
  mobile_user(email).update_column(:regions, csv)
end

Given("the phone {string} holds a website region-switch link for {string}") do |phone_name, code|
  # The website's own purpose (:login) — what UsersController#cross_site_link mints
  phone(phone_name).challenge = CrossSiteLink.new.generate("rahul@sharmafo.in", purpose: CrossSiteLink::PURPOSE,
                                                                                site: code, from: SiteRegistry.current_code)
end

Given("Rahul's investor access to Arka Capital is not approved") do
  InvestorAccess.where(user: mobile_user("rahul@sharmafo.in"), entity: arka[:fm]).update_all(approved: false)
end

Given("a fund manager {string} the investor has no access to") do |name|
  mobile_fund_manager(name)
end

Given("the Beta commitment has a document {string}") do |name|
  commitment = CapitalCommitment.joins(:fund).find_by!(funds: { name: "Beta Opportunities" })
  mobile_document!(commitment, name:, entity: commitment.entity)
end

# ── Requests ─────────────────────────────────────────────────────────────────

When("a phone that is not signed in asks {string}") do |path|
  mobile_request("Signed-out phone", :get, path)
end

When("the phone {string} asks for a link to the region {string}") do |phone_name, code|
  mobile_request(phone_name, :post, "/api/mobile/v1/cross_site_links", { site: code })
  # Kept on the phone for the redeem step, as the app keeps it between the two calls
  phone(phone_name).challenge = last_phone.json["token"] if last_phone.json["token"]
end

When("the phone {string} redeems the region link") do |phone_name|
  ph = phone(phone_name)
  # The target region has never seen this phone's token, so the call carries none
  ph.access_token = nil
  mobile_request(phone_name, :post, "/api/mobile/v1/session/cross_site", { token: ph.challenge, device: ph.device_attrs })
  ph.access_token = last_phone.json["access_token"] if last_phone.json["access_token"]
end

When("the phone {string} opens Home for the fund manager {string}") do |phone_name, name|
  mobile_request(phone_name, :get, "/api/mobile/v1/home?fund_manager_id=#{Entity.find_by!(name:).id}")
end

When("the phone {string} opens Documents for the fund manager {string}") do |phone_name, name|
  mobile_request(phone_name, :get, "/api/mobile/v1/documents?fund_manager_id=#{Entity.find_by!(name:).id}")
end

# ── Outcomes ─────────────────────────────────────────────────────────────────

Then("the phone sees the sites {string}") do |rows|
  got = last_phone.json["sites"].map { |s| "#{s['code']} #{s['label']} #{s['url']}" }
  expect(got).to eq(rows.split("; "))
end

Then("the phone is offered the regions {string}") do |csv|
  expect(last_phone.json["regions"].pluck("code")).to eq(csv.split(", "))
end

Then("the phone is offered the fund managers {string}") do |names|
  expect(last_phone.json["fund_managers"].pluck("name")).to eq(names.split(", "))
end

Given("{string} has uploaded a logo") do |name|
  entity = Entity.find_by!(name:)
  Rails.public_path.join("img/logo_big.png").open("rb") { |file| entity.update!(logo: file) }
end

Then("the fund manager {string} has a logo link") do |name|
  row = last_phone.json["fund_managers"].find { |f| f["name"] == name }
  expect(row["logo_url"]).to be_present, "got #{row}"
end

Then("the fund manager {string} has no logo link") do |name|
  row = last_phone.json["fund_managers"].find { |f| f["name"] == name }
  expect(row).to have_key("logo_url")
  expect(row["logo_url"]).to be_nil
end

Then("the Home is for the fund manager {string}") do |name|
  expect(last_phone.json["fund_manager_id"]).to eq(Entity.find_by!(name:).id)
end

Then("{string} has a live phone {string} in the region {string}") do |email, phone_name, code|
  device = mobile_user(email).mobile_devices.live.find_by!(install_id: phone(phone_name).install_id)
  expect(device.region_code).to eq(code)
end

Then("the first alert's sender is {string}") do |name|
  alert = last_phone.json.first
  expect(alert["sender"]).to eq(name)
  expect(alert["sender_id"]).to eq(Entity.find_by!(name:).id)
end
