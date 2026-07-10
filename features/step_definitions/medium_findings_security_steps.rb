# Step definitions for features/security/medium_findings_security_fixes.feature
# Model + policy level assertions of the M2 / M3 / M5 security fixes.

# Creates a user in the given entity and grants a role, reloading so has_cached_role? is fresh.
def msec_user(entity, role)
  user = FactoryBot.create(:user, entity: entity)
  user.add_role(role)
  user.reload
  user
end

# Creates a document in the entity, ensuring a folder exists (Document expects one).
def msec_document(entity, user)
  folder = Folder.where(entity: entity).first || FactoryBot.create(:folder, entity: entity)
  FactoryBot.create(:document, entity: entity, user: user, folder: folder, name: "MSec Doc #{rand(10_000)}")
end

# ── M2 ──────────────────────────────────────────────────────────────────────

Given('a document share for a security test exists') do
  entity = FactoryBot.create(:entity, name: "MSec M2 #{rand(10_000)}", enable_documents: true)
  admin  = msec_user(entity, :company_admin)
  doc    = msec_document(entity, admin)
  @msec_doc_share = DocShare.create!(document: doc, email: "m2@example.com", email_sent: true, view_count: 0)
end

When('a share token is generated with the default expiry') do
  @msec_token = DocShareTokenService.new.generate_token(@msec_doc_share.id)
end

When('a share token is generated that has already expired') do
  # Negative TTL => expires_at is in the past => verify raises ExpiredSignature.
  @msec_token = DocShareTokenService.new.generate_token(@msec_doc_share.id, expires_in: -1.second)
end

Then('the share token resolves to the doc share id') do
  expect(DocShareTokenService.new.verify_token(@msec_token).to_s).to eq(@msec_doc_share.id.to_s)
end

Then('the share token does not resolve') do
  expect(DocShareTokenService.new.verify_token(@msec_token)).to be_nil
end

# ── M3 ──────────────────────────────────────────────────────────────────────

Given('a company admin in a security test entity with a shared document') do
  @msec_alpha       = FactoryBot.create(:entity, name: "MSec Alpha #{rand(10_000)}", enable_documents: true)
  @msec_alpha_admin = msec_user(@msec_alpha, :company_admin)
  doc               = msec_document(@msec_alpha, @msec_alpha_admin)
  @msec_alpha_share = DocShare.create!(document: doc, email: "alpha@example.com", email_sent: true, view_count: 0)
end

Given('a different security test entity with its own shared document') do
  beta      = FactoryBot.create(:entity, name: "MSec Beta #{rand(10_000)}", enable_documents: true)
  beta_user = msec_user(beta, :company_admin)
  doc       = msec_document(beta, beta_user)
  @msec_beta_share = DocShare.create!(document: doc, email: "beta@example.com", email_sent: true, view_count: 0)
end

Then("the company admin's doc share scope includes only their own entity's share") do
  scoped = Pundit.policy_scope(@msec_alpha_admin, DocShare)
  expect(scoped).to include(@msec_alpha_share)
  expect(scoped).not_to include(@msec_beta_share)
end

# ── M5 ──────────────────────────────────────────────────────────────────────

Given('an investor access record in a managing entity') do
  @msec_mgmt   = FactoryBot.create(:entity, name: "MSec Mgmt #{rand(10_000)}")
  inv_entity   = FactoryBot.create(:entity, name: "MSec InvEnt #{rand(10_000)}")
  investor     = FactoryBot.create(:investor, entity: @msec_mgmt, investor_entity: inv_entity)
  @msec_ia     = FactoryBot.create(:investor_access, entity: @msec_mgmt, investor: investor,
                                   approved: false, user: nil, email: "grantee@example.com")
end

Given('a company admin of that managing entity') do
  @msec_ia_admin = msec_user(@msec_mgmt, :company_admin)
end

Given('a regular employee of that managing entity') do
  @msec_ia_emp = msec_user(@msec_mgmt, :employee)
end

Then('the company admin may create and approve the investor access') do
  policy = InvestorAccessPolicy.new(@msec_ia_admin, @msec_ia)
  expect(policy.create?).to be_truthy
  expect(policy.approve?).to be_truthy
end

Then('the employee may not create or approve the investor access') do
  policy = InvestorAccessPolicy.new(@msec_ia_emp, @msec_ia)
  expect(policy.create?).to be_falsey
  expect(policy.approve?).to be_falsey
end

# ── M10 ─────────────────────────────────────────────────────────────────────

Given('a decorated entity collection for a security test') do
  FactoryBot.create(:entity, name: "MSec Deco A #{rand(10_000)}")
  FactoryBot.create(:entity, name: "MSec Deco B #{rand(10_000)}")
  @msec_deco = TemplateDecorator.new(Entity.all)
end

Then('filtering by the column {string} is allowed') do |col|
  expect(TemplateDecorator.safe_filter_column(Entity.all, col)).to eq(col)
  # End-to-end: a valid where_ filter returns a collection without error.
  result = @msec_deco.send(:"where_#{col}_eq_Nonexistent")
  expect(result).to respond_to(:each)
end

Then('filtering by an injected field returns no rows and raises no SQL error') do
  expect(TemplateDecorator.safe_filter_column(Entity.all, "1=1) OR (1=1--")).to be_nil
  result = @msec_deco.send(:"where_1=1) OR (1=1--_eq_x")
  arr = result.respond_to?(:to_a) ? result.to_a : Array(result)
  expect(arr).to be_empty
end
