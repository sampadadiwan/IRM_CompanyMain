class DocShare < ApplicationRecord
  belongs_to :document

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
end
