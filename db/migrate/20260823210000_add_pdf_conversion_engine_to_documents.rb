class AddPdfConversionEngineToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :pdf_conversion_engine, :string, default: "libreoffice", null: false
  end
end
