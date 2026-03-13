def deep_strip_aj_keys(obj)
  case obj
  when Hash
    obj.reject { |k, _| k.to_s.start_with?('_aj_') }
       .transform_values { |v| deep_strip_aj_keys(v) }
  when Array
    obj.map { |v| deep_strip_aj_keys(v) }
  else
    obj
  end
end

Given('I filter the AEs') do
  @document_name = "account_entries.xlsx"
  visit account_entries_path(filter: true)
  find('#q_c_0_v_0_value').set('01/01/2020')
  find('button.search-button[type="submit"]').click
  sleep(2)
end

IGNORED_JOBS = [DocumentPostCreateJob].freeze

def run_enqueued_download_jobs
  # Step 1: run ModelDownloadJob manually (keyword args need special handling)
  download_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == ModelDownloadJob }
  ActiveJob::Base.queue_adapter.enqueued_jobs.reject! { |job| job[:job] == ModelDownloadJob }
  download_jobs.each do |job|
    raw = job[:kwargs] || job[:args].find { |a| a.is_a?(Hash) } || {}
    args = deep_strip_aj_keys(raw).symbolize_keys
    job[:job].new.perform(**args)
  end

  # Step 2: drain everything else (Noticed::EventJob -> ActionMailer::MailDeliveryJob chain)
  # except jobs we know are unrelated and have incompatible signatures
  loop do
    pending = ActiveJob::Base.queue_adapter.enqueued_jobs.reject { |job| IGNORED_JOBS.include?(job[:job]) || job[:job] == ModelDownloadJob }
    break if pending.empty?

    ActiveJob::Base.queue_adapter.enqueued_jobs.reject! { |job| pending.include?(job) }
    pending.each do |job|
      job_data = {
        "job_class"  => job[:job].name,
        "job_id"     => job[:job_id],
        "queue_name" => job[:queue],
        "arguments"  => job[:args]
      }
      ActiveJob::Base.execute(job_data)
    end
  end
end

Given('I download all the AEs') do
  @docs_count = Document.count
  expect(page).to have_content('Download', wait: 5)
  ActiveJob::Base.queue_adapter = :test
  click_on 'Download'
  run_enqueued_download_jobs
  ActiveJob::Base.queue_adapter = :inline
end

Given('I download all the pivoted AEs') do
  @document_name = "account_entries_pivot.xlsx"
  @docs_count = Document.count
  ActiveJob::Base.queue_adapter = :test
  click_on("Download")
  click_on("Export All")
  run_enqueued_download_jobs
  ActiveJob::Base.queue_adapter = :inline
end

Then('a new file is generated for the download') do
  expect(Document.count).to eq(@docs_count + 1)
  @doc = Document.order(:created_at).last
  expect(@doc.name).to include(@document_name.split('.').first)
end

Given('the user can receive emails') do
  @user ||= User.first
  @user.entity.entity_setting.update_columns(sandbox: false)
end

Then('I get an email with the file attached') do
  @user ||= User.first
  current_email = nil
  emails_sent_to(@user.email).each do |email|
    puts "#{email.subject} #{email.to} #{email.cc} #{email.bcc}"
    current_email = email if email.subject.include?("Your Account entries download is ready")
  end
  puts "No email found for #{@user.email} with subject 'Your Account entries download is ready'" if current_email.nil?
  expect(current_email.body).to include "Please find the XL of the"


  puts "Checking for attachment in #{current_email}"
  attachment_filenames = current_email.attachments.map(&:filename)
  expect(attachment_filenames.select{ |filename| filename.include?(@document_name) || filename.downcase.include?(@document_name.downcase)}).to be_present, "Expected attachment #{@document_name}, but got #{attachment_filenames.inspect}"
end

Given('I filter and pivot the AEs') do
  visit account_entries_path(filter: true)
  find('#q_c_0_v_0_value').set('01/01/2020')
  check('q_pivot')
  sleep(0.5)
  find('button.search-button[type="submit"]').click
  sleep(2)
end
