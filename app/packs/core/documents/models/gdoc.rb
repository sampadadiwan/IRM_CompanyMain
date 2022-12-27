require "googleauth"

class Gdoc
  def init
    # session = GoogleDrive::Session.from_config("/home/thimmaiah/work/IRM/config/google-config.json")
    session = GoogleDrive::Session.from_service_account_key("/home/thimmaiah/work/IRM/config/google-config.json")

    session.files.each do |file|
      Rails.logger.debug file.title
      file.delete
    end

    file = session.upload_from_file("public/sample_uploads/GrantLetter.docx", "GrantLetter.docx", convert: false)

    file.acl.each do |entry|
      Rails.logger.debug [entry.type, entry.email_address, entry.role]
      # => e.g. ["user", "example1@gmail.com", "owner"]
    end

    file.acl.push({ type: "user", email_address: "thimmaiah@gmail.com", role: "writer" })
    file.acl.push({ type: "user", email_address: "ausang@caphive.com", role: "reader" })
  end
end
