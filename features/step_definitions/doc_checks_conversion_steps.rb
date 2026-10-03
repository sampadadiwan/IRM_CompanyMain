# Steps for converting legacy Doc Questions (features/core/doc_checks_conversion.feature).
# Worked examples H10, H11, X9 in openspec/changes/document-checks/design.md#worked-examples

# | document | type | question | response hint |
Given("the entity has the Doc Questions:") do |table|
  table.hashes.each do |row|
    DocQuestion.create!(entity: @entity, owner: @entity, for_class: "InvestorKyc", document_name: row["document"],
                        qtype: row["type"], question: row["question"], response_hint: row["response hint"].presence, tags: "KYC")
  end
end

When("the Doc Questions conversion runs for the entity") do
  @conversion = DocChecks::LegacyConverter.call(entity: @entity, execute: false)
end

When("the Doc Questions conversion runs for the entity with execute") do
  @conversion = DocChecks::LegacyConverter.call(entity: @entity, execute: true)
end

# | question | action | field |
Then("the conversion report should convert:") do |table|
  converted = @conversion[:converted].map do |row|
    question = DocQuestion.find(row[:question_id]).question
    { "question" => question, "action" => row[:action], "field" => row[:field].to_s }
  end
  expect(converted).to eq(table.hashes)
end

# | question | reason |
Then("the conversion report should not convert:") do |table|
  skipped = @conversion[:not_converted].map { |row| { "question" => DocQuestion.find(row[:question_id]).question, "reason" => row[:reason] } }
  expect(skipped).to eq(table.hashes)
end

Then("the entity should have {int} document checks") do |count|
  expect(DocCheck.where(entity: @entity).count).to eq(count)
end

Then("{int} Doc Questions should be logged as not converted") do |count|
  expect(DocCheckConversionLog.where(entity: @entity).count).to eq(count)
end
