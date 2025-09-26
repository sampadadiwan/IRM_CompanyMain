require 'rails_helper'

RSpec.describe "AccountEntries API", type: :request do
  let(:entity) { FactoryBot.create(:entity, entity_type: "Investment Fund") }
  let(:inv_entity) { FactoryBot.create(:entity, entity_type: "Company") }
  let(:user) { FactoryBot.create(:user, entity: entity, password: "password") }
  let(:fund) { FactoryBot.create(:fund, entity: entity, unit_types: "Class A,Class B") } # Ensure unit_types is set for validation
  let(:investor) { FactoryBot.create(:investor, entity: entity, investor_entity_id: inv_entity.id) }
  let(:investor_kyc) { FactoryBot.create(:investor_kyc, investor: investor, entity: entity) }

  let!(:capital_commitment1) { FactoryBot.create(:capital_commitment, fund: fund, entity: fund.entity, investor: investor, investor_kyc: investor_kyc, folio_id: "CC-001", unit_type: "Class A") }
  let!(:capital_commitment2) { FactoryBot.create(:capital_commitment, fund: fund, entity: fund.entity, investor: investor, investor_kyc: investor_kyc, folio_id: "CC-002", unit_type: "Class B") }

  let!(:account_entry1) { FactoryBot.create(:account_entry, fund: fund, entity: entity, capital_commitment_id: capital_commitment1.id, folio_id: "CC-001", reporting_date: Date.today-2.day, entry_type: "Capital Call", amount: 1000) }
  let!(:account_entry2) { FactoryBot.create(:account_entry, fund: fund, entity: entity, capital_commitment_id: capital_commitment1.id, folio_id: "CC-001", reporting_date: Date.today-1.day, entry_type: "Distribution", amount: 500) }
  let!(:account_entry3) { FactoryBot.create(:account_entry, fund: fund, entity: entity, reporting_date: Date.today, entry_type: "Expense", amount: 500) }

  let(:token) do
    post "/users/tokens/sign_in",
      params: { email: user.email, password: "password" }.to_json,
      headers: { "Content-Type" => "application/json" }
    JSON.parse(response.body)["token"]
  end

  def auth_headers(auth_token: nil)
    auth_token ||= token
    {
      "Authorization" => "#{auth_token}",
      "Content-Type" => "application/json",
      "Accept" => "application/json"
    }
  end

  before do
    entity.permissions.set(:enable_funds)
    entity.save!
    user.permissions.set(:enable_funds)
    user.add_role(:employee)
    user.add_role(:company_admin)
    user.curr_role = "employee"
    user.save!
    raise "Failed to get token" unless token
  end

  describe "GET /account_entries" do
    it "returns all account entries for the fund" do
      get "/account_entries", params: { fund_id: fund.id, page: 1, per_page: 10 }, headers: auth_headers
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.size).to be >= 2
      expect(json.map { |ae| ae["id"] }).to include(account_entry1.id, account_entry2.id)
    end

    it "filters by entry_type" do
      get "/account_entries", params: { entry_type: "Capital Call" }, headers: auth_headers
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.map { |ae| ae["entry_type"] }).to all(eq("Capital Call"))
    end

    it "filters by commitment nil" do
      get "/account_entries?fund_id=#{fund.id}&q%5Bc%5D%5B0%5D%5Ba%5D%5B0%5D%5Bname%5D=capital_commitment_id&q%5Bc%5D%5B0%5D%5Bp%5D=null&q%5Bc%5D%5B0%5D%5Bv%5D%5B0%5D%5Bvalue%5D=true&q%5Bc%5D%5B1%5D%5Ba%5D%5B0%5D%5Bname%5D=reporting_date&q%5Bc%5D%5B1%5D%5Bp%5D=gt&q%5Bc%5D%5B1%5D%5Bv%5D%5B0%5D%5Bvalue%5D=01%2F07%2F2021&pivot=false&show_chart=false&hide_parent=false&hide_commitment=false&show_breakdown=false&template=index_group&group_by=name&agg_type=sum&agg_type=sum&agg_field=amount&button=", headers: auth_headers
      expect(response).to have_http_status(:ok)
      byebug
      json = JSON.parse(response.body)
      expect(json.map { |ae| ae["id"] }).not_to include(account_entry1.id, account_entry2.id)
      expect(json.map { |ae| ae["id"] }).to include(account_entry3.id)
      expect(json.map { |ae| ae["capital_commitment_id"] }).to all(be_nil)
    end

    it "filters by commitment present" do
      get "/account_entries?fund_id=#{fund.id}&q%5Bc%5D%5B0%5D%5Ba%5D%5B0%5D%5Bname%5D=capital_commitment_id&q%5Bc%5D%5B0%5D%5Bp%5D=null&q%5Bc%5D%5B0%5D%5Bv%5D%5B0%5D%5Bvalue%5D=false&q%5Bc%5D%5B1%5D%5Ba%5D%5B0%5D%5Bname%5D=reporting_date&q%5Bc%5D%5B1%5D%5Bp%5D=gt&q%5Bc%5D%5B1%5D%5Bv%5D%5B0%5D%5Bvalue%5D=01%2F07%2F2021&pivot=false&show_chart=false&hide_parent=false&hide_commitment=false&show_breakdown=false&template=index_group&group_by=name&agg_type=sum&agg_type=sum&agg_field=amount&button=", headers: auth_headers
      expect(response).to have_http_status(:ok)
      byebug
      json = JSON.parse(response.body)
      expect(json.map { |ae| ae["id"] }).to include(account_entry1.id, account_entry2.id)
      expect(json.map { |ae| ae["id"] }).not_to include(account_entry3.id)
      expect(json.map { |ae| ae["capital_commitment_id"] }).to include(account_entry1.capital_commitment_id, account_entry2.capital_commitment_id)
    end

    it "filters by reporting_date" do
      get "/account_entries?fund_id=#{fund.id}&q%5Bc%5D%5B0%5D%5Ba%5D%5B0%5D%5Bname%5D=reporting_date&q%5Bc%5D%5B0%5D%5Bp%5D=lt&q%5Bc%5D%5B0%5D%5Bv%5D%5B0%5D%5Bvalue%5D=#{Date.today.day}%2F#{Date.today.month}%2F#{Date.today.year}&pivot=false&show_chart=false&hide_parent=false&hide_commitment=false&show_breakdown=false&template=index_group&group_by=name&agg_type=sum&agg_type=sum&agg_field=amount&button=", headers: auth_headers
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.map { |ae| ae["id"] }).to include(account_entry1.id, account_entry2.id)
      expect(json.map { |ae| ae["id"] }).not_to include(account_entry3.id)
    end

    it "filters by name and folio id" do
      get "/account_entries?fund_id=#{fund.id}&q%5Bc%5D%5B0%5D%5Ba%5D%5B0%5D%5Bname%5D=folio_id&q%5Bc%5D%5B0%5D%5Bp%5D=eq&q%5Bc%5D%5B0%5D%5Bv%5D%5B0%5D%5Bvalue%5D=CC-001&q%5Bc%5D%5B1%5D%5Ba%5D%5B0%5D%5Bname%5D=entry_type&q%5Bc%5D%5B1%5D%5Bp%5D=eq&q%5Bc%5D%5B1%5D%5Bv%5D%5B0%5D%5Bvalue%5D=Distribution&q%5Bc%5D%5B2%5D%5Ba%5D%5B0%5D%5Bname%5D=reporting_date&q%5Bc%5D%5B2%5D%5Bp%5D=gt&q%5Bc%5D%5B2%5D%5Bv%5D%5B0%5D%5Bvalue%5D=01%2F07%2F2021&pivot=false&show_chart=false&hide_parent=false&hide_commitment=false&show_breakdown=false&template=index_group&group_by=name&agg_type=sum&agg_type=sum&agg_field=amount&button=", headers: auth_headers
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.map { |ae| ae["id"] }).to include(account_entry2.id)
      expect(json.map { |ae| ae["id"] }).not_to include(account_entry1.id)
      expect(json.map { |ae| ae["id"] }).not_to include(account_entry3.id)
      expect(json.map { |ae| ae["capital_commitment_id"] }).to include(account_entry2.capital_commitment_id)
    end
  end

  describe "GET /account_entries/:id" do
    it "returns the account entry" do
      get "/account_entries/#{account_entry1.id}", headers: auth_headers
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["id"]).to eq(account_entry1.id)
      expect(json["folio_id"]).to eq(account_entry1.folio_id)
    end

    it "returns 403 for a non-existent account entry" do
      get "/account_entries/non_existent_id", headers: auth_headers
      expect(response).to have_http_status(403)
    end
  end

end
