class XlExporter
  DATA = [["Tim", 20], ["Dan", 30], ["Rich", 40]].freeze
  def self.export
    open_book = Spreadsheet.open('test.xls')
    new_row_index = 0

    header = %w[Name Age]
    open_book.worksheet(0).row(new_row_index).concat(header)

    DATA.each do |d|
      new_row_index += 1
      open_book.worksheet(0).row(new_row_index).concat([d[0], d[1]])

      Rails.logger.debug { "Wrote row #{new_row_index}" }
    end

    open_book.write('test_new.xls')
  end
end
