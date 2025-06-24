# app/packs/core/documents/services/xlsx_to_json_config.rb

class XlsxToJsonConfig
  # Defines the schema for representing the non-data structure of an XLSX file in JSON.
  # This schema includes workbook, sheet, column, row, cell, and merge properties,
  # along with comprehensive style definitions.
  SCHEMA = {
    "workbookName" => "string",
    "styles" => {
      "styleId1" => { # Example styleId
        "font" => {
          "name" => "string",
          "size" => "number",
          "bold" => "boolean",
          "italic" => "boolean",
          "underline" => "boolean",
          "color" => "string" # Hex color code (e.g., "FF0000")
        },
        "fill" => {
          "type" => "string",    # e.g., "pattern"
          "pattern" => "string", # e.g., "solid"
          "fgColor" => "string", # Hex color code
          "bgColor" => "string"  # Hex color code
        },
        "border" => {
          "top" => { "style" => "string", "color" => "string" },
          "bottom" => { "style" => "string", "color" => "string" },
          "left" => { "style" => "string", "color" => "string" },
          "right" => { "style" => "string", "color" => "string" }
        },
        "alignment" => {
          "horizontal" => "string", # "left", "center", "right", "justify"
          "vertical" => "string",   # "top", "middle", "bottom"
          "wrapText" => "boolean",
          "indent" => "number",
          "shrinkToFit" => "boolean",
          "textRotation" => "number" # Degrees
        },
        "numFmt" => "string", # Excel number format code (e.g., "0.00", "yyyy-mm-dd")
        "protection" => {
          "locked" => "boolean",
          "hidden" => "boolean"
        }
      }
      # ... other style definitions would follow this pattern
    },
    "sheets" => [
      {
        "name" => "string",
        "index" => "number", # 0-based index
        "visibility" => "string", # "visible", "hidden", "veryHidden"
        "properties" => {
          "defaultColWidth" => "number",
          "defaultRowHeight" => "number",
          "showGridLines" => "boolean",
          "zoomScale" => "number" # Percentage (e.g., 100)
        },
        "columns" => [
          {
            "index" => "number", # 1-based column number
            "width" => "number",
            "hidden" => "boolean",
            "styleId" => "string" # Reference to a style in "styles"
          }
        ],
        "rows" => [
          {
            "index" => "number", # 1-based row number
            "height" => "number",
            "hidden" => "boolean",
            "styleId" => "string" # Reference to a style in "styles"
          }
        ],
        "cells" => [
          {
            "row" => "number", # 1-based row number
            "col" => "number", # 1-based column number
            "styleId" => "string", # Reference to a style in "styles"
            "formula" => "string", # e.g., "=SUM(A1:A10)"
            "hyperlink" => "string", # URL
            "comment" => {
              "author" => "string",
              "text" => "string"
            }
          }
        ],
        "merges" => [
          {
            "from" => { "row" => "number", "col" => "number" },
            "to" => { "row" => "number", "col" => "number" }
          }
        ]
      }
      # ... other sheet definitions would follow this pattern
    ]
  }.freeze # Freeze the hash to make it immutable
end
