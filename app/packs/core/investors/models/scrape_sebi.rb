require 'selenium-webdriver'
require 'open-uri'
require 'nokogiri'

class ScrapeSebi
  # Function to scrape the data from the SEBI website
  def scrape_data(driver)
    records = []

    driver.find_elements(css: 'table.table tr').each_with_index do |tr, index|
      next if index.zero?

      td_elements = tr.find_elements(css: 'td')
      return if td_elements.empty?

      record = {
        name: td_elements[0].text,
        registration_no: td_elements[1].text,
        address: td_elements[2].text,
        contact_person: td_elements[3].text,
        correspondence_address: td_elements[4].text,
        validity: td_elements[5].text
      }
      records << record
    end

    records
  end

  def scrape
    # Initialize the headless Chrome browser
    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument('--headless')
    driver = Selenium::WebDriver.for(:chrome, options:)

    # Navigate to the first page
    driver.get('https://www.sebi.gov.in/sebiweb/other/OtherAction.do?doRecognisedFpi=yes&intmId=16')

    # Scrape the data from all pages up to 53
    all_data = []
    1.upto(53) do |page_num|
      Rails.logger.debug { "Scraping page #{page_num}..." }
      data = scrape_data(driver)
      all_data += data

      # Click the "Next" button
      next_button = driver.find_element(css: 'a[title="Next"]')
      next_button&.click

      # Wait for the new page to load
      sleep(5)
    end

    # Close the browser
    driver.quit

    # Create an XLS file and add the scraped data
    package = Axlsx::Package.new
    workbook = package.workbook
    worksheet = workbook.add_worksheet(name: 'SEBI Registered AIFs')

    # Set column widths
    worksheet.column_widths 20, 20, 50, 30, 50, 30

    # Add headers
    worksheet.add_row ['Name', 'Registration No.', 'Address', 'Contact Person', 'Correspondence Address', 'Validity']

    # Add scraped data
    all_data.each do |row|
      worksheet.add_row [row[:name], row[:registration_no], row[:address], row[:contact_person], row[:correspondence_address], row[:validity]]
    end

    # Save the XLS file
    package.serialize('sebi_registered_aifs.xlsx')
  end
end
