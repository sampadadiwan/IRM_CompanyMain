When("I convert a sample docx to PDF via the M365 Graph engine") do
  docx_path = Rails.public_path.join("sample_uploads/SPA.docx").to_s
  @m365_pdf_path = Rails.root.join("tmp/m365_live_test_#{SecureRandom.hex(4)}.pdf").to_s

  @m365_result = M365PdfConversion.call(docx_path: docx_path, pdf_path: @m365_pdf_path)
end

Then("the M365 conversion should succeed") do
  expect(@m365_result.success?).to eq(true), "M365 Graph conversion failed: #{@m365_result[:errors]}"
end

Then("the resulting PDF file should be non-empty") do
  expect(File.exist?(@m365_pdf_path)).to eq(true)
  expect(File.size(@m365_pdf_path)).to be > 1_000
end

After("@m365_live") do
  File.delete(@m365_pdf_path) if @m365_pdf_path && File.exist?(@m365_pdf_path)
end
