def sample_aml_get_report_response(url = nil)
  if url.nil?
    file_path = './public/sample_uploads/Offer_1_SPA.pdf'
    doc = Document.create!(entity: Investor.first.entity, owner: Investor.first, name: "Dummy file", file: File.open(file_path, "rb"), folder: Investor.first.document_folder, user_id: User.first.id)
    url = doc.file.url
  end
  OpenStruct.new(
    read_body: "[{\"type\":\"aml\",\"action\":\"verify_with_source\",\"result\":{\
      \"hits\":\"json url\",\"filters\":{\"types\":[\"sanctions\",\"pep\",\"warnings\",\"adverse_media\"],\
      \"entity_type\":\"individual\",\"name_fuzziness\":\"1\",\"birth_year_fuzziness\":\"2\"},\
      \"total_hits\":4,\"profile_pdf\":\"#{url}\",\"search_term\":\"Dumy Kyc name\",\
      \"match_status\":\"potential_match\"},\"status\":\"completed\",\
      \"task_id\":\"e1429efc-bad9-4b00-aaa6-1cc348954d16\",\
      \"group_id\":\"808c0a3f-37f9-4925-abb7-e69bd14dfcb4\",\
      \"created_at\":\"2024-12-19T18:36:22+05:30\",\
      \"request_id\":\"7e32d987-ee74-4d59-83a3-08e2402f625c\",\
      \"completed_at\":\"2024-12-19T18:36:31+05:30\"}]"
  )
end

def sample_aml_get_async_response
  OpenStruct.new(read_body: "{\"request_id\":\"7e32d987-ee74-4d59-83a3-08e2402f625c\"}")
end

def mock_pdf_file
  file_path = Rails.root.join('public/sample_uploads/Offer_1_SPA.pdf')
  @doc = Document.create!(
    entity: Investor.first.entity,
    owner: Investor.first,
    name: "Dummy file",
    file: File.open(file_path, "rb"),
    folder: Investor.first.document_folder,
    user_id: User.first.id
  )

  url = @doc.file.url

  allow(URI).to receive(:parse).and_wrap_original do |original_method, url|
    if url =~ /\.pdf$/
      instance_double(URI::HTTPS, open: File.open(file_path), query: "param1=value1")
    else
      original_method.call(url)
    end
  end

  url
end

# Shared setup for AML stubbing
def mock_aml
  p "upload server - #{ENV["UPLOAD_SERVER"]}"
  if ENV["UPLOAD_SERVER"].to_s == "app"
    url = mock_pdf_file
    allow_any_instance_of(AmlApiResponseService).to receive(:get_report_response).and_return(sample_aml_get_report_response(url))
  else
    allow_any_instance_of(AmlApiResponseService).to receive(:get_report_response).and_return(sample_aml_get_report_response(nil))
  end

  allow_any_instance_of(AmlApiResponseService).to receive(:get_async_response).and_return(sample_aml_get_async_response)
end

Given('the entity has aml enabled {string}') do |aml_enabled|
  @entity ||= Entity.first
  @entity.entity_setting.aml_enabled = aml_enabled == "true"
  @entity.entity_setting.save!
end

Then('aml report is not generated for the investor kyc') do
  @investor_kyc = InvestorKyc.last
  expect(@investor_kyc.documents.where("name like ?", "%AML Report%").count).to eq(0)
  expect(Document.where("name like ?", "%AML Report%").count).to eq(@aml_docs_count)
end


Then('aml report is generated for the investor kyc') do
  mock_aml
  @investor_kyc = InvestorKyc.last
  expect(@investor_kyc.documents.where("name like ?", "%AML Report%").count > 0).to eq(true)
  if @kyc_aml_docs_count.present?
    expect(@investor_kyc.documents.where("name like ?", "%AML Report%").count == @kyc_aml_docs_count + 1).to eq(true)
  end
  expect(Document.where("name like ?", "%AML Report%").count > @aml_docs_count).to eq(true)
end

Given('I bulk generate aml reports for investor kycs') do
  mock_aml
  @amls = {}
  InvestorKyc.all.each do |ik|
    # store count of kycs aml reports documents to validate later
    if ik.full_name.present?
      @amls[ik.id] = ik.documents.where("name like ?", "%AML Report%").count
    end

  end
  visit("/investor_kycs?q%5Bc%5D%5B0%5D%5Ba%5D%5B0%5D%5Bname%5D=PAN&q%5Bc%5D%5B0%5D%5Bp%5D=null&q%5Bc%5D%5B0%5D%5Bv%5D%5B0%5D%5Bvalue%5D=false&button=") # pan not NULL
  click_on("Bulk Actions")
  click_on("Generate AML Reports")
  click_on("Proceed")
end

Then('Aml report should be generated for the kycs that have full name') do
  mock_aml
  sleep(5)
  @amls.each do |ik_id, count|
    kyc = InvestorKyc.find(ik_id)
    kyc.documents.where("name like ?", "%AML Report%").count == count + 1
  end
end

Given('I update the last investor kycs name to {string}') do |newname|
  mock_aml
  @investor_kyc = InvestorKyc.last
  @kyc_aml_docs_count = @investor_kyc.documents.where("name like ?", "%AML Report%").count
  visit(investor_kyc_path(@investor_kyc))
  click_on("Edit")
  class_name = @investor_kyc.type_from_kyc_type.underscore

  fill_in("#{class_name}_full_name", with: newname)
  click_on("Next")
  fill_in("#{class_name}_bank_branch", with: "new branch")
  click_on("Next")
  click_on("Save")
  #sleep(1)
  expect(page).to have_content("successfully")
end

Given('I create a new InvestorKyc {string} to trigger aml report generation') do |args|
  mock_aml
  @aml_docs_count = Document.all.where("name like ?", "%AML Report%").count

  @temp_investor_kyc = FactoryBot.build(:investor_kyc, entity: @entity, kyc_type: "individual")
  key_values(@temp_investor_kyc, args)
  @temp_investor_kyc.full_name = nil if @temp_investor_kyc.full_name == "nil"
  puts "\n########### KYC ############"
  puts @temp_investor_kyc.to_json

  class_name = @temp_investor_kyc.type_from_kyc_type.underscore

  visit(investor_kycs_path)
  click_on("New KYC")
  click_on("Individual")
  #sleep(2)
  select(@temp_investor_kyc.investor.investor_name, from: "#{class_name}_investor_id")
  fill_in("#{class_name}_full_name", with: @temp_investor_kyc.full_name) unless @temp_investor_kyc.full_name.nil?
  fill_in("#{class_name}_PAN", with: @temp_investor_kyc.PAN)
  fill_in("#{class_name}_birth_date", with: @temp_investor_kyc.birth_date)
  click_on("Next")

  fill_in("#{class_name}_address", with: @temp_investor_kyc.address)
  fill_in("#{class_name}_corr_address", with: @temp_investor_kyc.corr_address)
  fill_in("#{class_name}_bank_name", with: @temp_investor_kyc.bank_account_number)
  fill_in("#{class_name}_bank_branch", with: @temp_investor_kyc.bank_account_number)
  fill_in("#{class_name}_bank_account_number", with: @temp_investor_kyc.bank_account_number)
  fill_in("#{class_name}_ifsc_code", with: @temp_investor_kyc.ifsc_code)
  click_on("Next")
  fill_in("#{class_name}_expiry_date", with: @temp_investor_kyc.expiry_date)
  fill_in("#{class_name}_comments", with: @temp_investor_kyc.comments)
  click_on("Save")
  #sleep(1)
  expect(page).to have_content("successfully")
  sleep(2)
end

Then('I update full name to nil for the KYC') do
  @last_kyc = InvestorKyc.last
  @last_kyc.update_column(:full_name, nil)
end