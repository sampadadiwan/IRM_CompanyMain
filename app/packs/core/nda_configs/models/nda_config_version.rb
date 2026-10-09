# frozen_string_literal: true

# Records a versioned snapshot of an NDA PDF upload for audit trail purposes.
# Each time a GP uploads a new PDF on an existing NDA config, a version record
# is created storing the Shrine file reference, the version number, who uploaded
# it, and whether existing accepted investors must re-sign.
#
# The nda_document_data column stores raw Shrine JSON (pointer to the S3 object),
# NOT a Shrine attachment — URL generation for historical PDFs uses
# FileUploader::UploadedFile.new(JSON.parse(record.nda_document_data)).
#
# @see NdaConfig#nda_config_versions
# @see DocumentsController#acceptance_version_current? — queries resign_required
#   across version ranges to determine acceptance validity
class NdaConfigVersion < ApplicationRecord
  # Changed: New model for NDA version audit trail.
  # Why: Tracks every PDF upload with metadata so compliance can answer
  #   "what PDF was version N, who uploaded it, and did it require re-signing?"

  # The NDA config this version belongs to
  belongs_to :nda_config

  # The GP user who uploaded this version's PDF
  belongs_to :uploaded_by, class_name: "User"

  # One version number per NDA config — mirrors the unique DB index
  validates :version, uniqueness: { scope: :nda_config_id, message: "already exists for this NDA config" }
  validates :nda_document_data, presence: true
end
