require 'zip'
require 'fileutils'

# Trigger the DocumentDownloadJob synchronously
When('I trigger the download for {string}') do |folder_name|
  @folder = Folder.find_by!(name: folder_name)
  # Clear existing tmp jobs if any
  FileUtils.rm_rf(Dir.glob("tmp/#{@folder.id}_*"))

  @job = DocumentDownloadJob.new
  @job.perform(@folder.id, @user.id)
end

Then('the download job should complete successfully') do
  @uploaded_doc = Document.where(owner_tag: "Generated").order(created_at: :desc).first
  expect(@uploaded_doc).to be_present
  expect(@uploaded_doc.name).to include("Download-#{@folder.name}")
end

And('the ZIP file should have the following structure:') do |table|
  # Download the file from Shrine
  zip_tempfile = @uploaded_doc.file.download

  expected_paths = table.hashes.map { |h| h['path'] }

  # The job currently puts files under "Full/Path/To/Folder/..."
  # e.g. "Root Folder/DocRoot.docx" if Root Folder is at /Root Folder

  Zip::File.open(zip_tempfile.path) do |zip_file|
    actual_paths = zip_file.map(&:name)
    puts "Actual paths in ZIP: #{actual_paths.inspect}"

    expected_paths.each do |expected_path|
      # Note: We need to match the folder path too since it's preserved
      # If Root Folder is at "/", then its full_path is "/Root Folder"
      # DocumentDownloadJob uses doc.folder_full_path, which starts with /
      # but we delete_prefix("#{@tmp_dir}/") so it will start with "Root Folder/..."

      # The table provides paths like "DocRoot.docx", but they will probably be "Root Folder/DocRoot.docx"
      # Let's adjust expected_path to include the root folder if needed, or check for inclusion.

      full_expected_path = "#{@folder.name}/#{expected_path}".delete_prefix("/")
      expect(actual_paths).to include(full_expected_path)
    end
  end
ensure
  zip_tempfile&.close
  zip_tempfile&.unlink if zip_tempfile&.respond_to?(:unlink)
end

And('the temporary directory should be cleaned up') do
  remaining = Dir.glob("tmp/#{@folder.id}_*")
  expect(remaining).to be_empty, "Temporary directories were not cleaned up: #{remaining.inspect}"
end

Given('there is a document {string} in folder {string}') do |doc_args, folder_name|
  @entity ||= Entity.first
  target_folder = Folder.find_by!(name: folder_name, entity: @entity)
  @document = Document.new(entity: @entity, folder: target_folder, user: @user || User.first)
  # Default file if not provided
  @document.file = File.open("public/sample_uploads/GrantLetter.docx")
  key_values(@document, doc_args)
  @document.save!
end

Given('given there is a large document {string} under the folder') do |args|
  @entity ||= Entity.first
  params = args.split(';').map { |s| s.split('=') }.to_h
  name = params['name'] || "LargeFile"
  size_gb = params['size'].to_f # e.g. 2.1

  # Create a sparse file with .zip extension to pass MIME validation
  sparse_file_path = Rails.root.join("tmp", "#{name}.zip")
  # Use dd to create a sparse file of the target size
  system("dd if=/dev/zero of=#{sparse_file_path} bs=1 count=0 seek=#{ (size_gb * 1024 * 1024 * 1024).to_i }")

  @document = Document.new(
    entity: @entity,
    name: name,
    folder: @folder,
    user: @user,
    owner_tag: "Generated"
  )
  @document.file = File.open(sparse_file_path)
  @document.save!

  # Cleanup the sparse file from tmp after attachment
  FileUtils.rm(sparse_file_path)
end

Then('the ZIP file should contain {string} with Zip64 support') do |filename|
  zip_tempfile = @uploaded_doc.file.download

  Zip::File.open(zip_tempfile.path) do |zip_file|
    # Look for the file. It will be under "@folder.name/filename"
    full_path = "#{@folder.name}/#{filename}".delete_prefix("/")
    entry = zip_file.find_entry(full_path)
    expect(entry).to be_present
    puts "Large file entry size: #{entry.size}"
    # Verification of size to ensure it's > 2GB
    expect(entry.size).to be > 2 * 1024 * 1024 * 1024
  end
ensure
  zip_tempfile&.close
  zip_tempfile&.unlink if zip_tempfile&.respond_to?(:unlink)
end
