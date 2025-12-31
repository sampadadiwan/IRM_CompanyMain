# frozen_string_literal: true

class AiPresentation < ApplicationRecord
  belongs_to :chat
  belongs_to :entity

  validates :content_html, presence: true
end
