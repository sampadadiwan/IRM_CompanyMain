# KPI Reporting: New Features & User Guide Updates

## 1. Multi-Portfolio KPI Reminders
You can now send KPI reporting reminders to multiple portfolio companies simultaneously.

- **Bulk Actions**: From the main Investors list, use the "Portfolio Assistant" or "Actions" dropdown to find the **"Send KPI Reminder"** option.
- **Multi-Select**: A new interface allows you to select multiple portfolio companies and specify the **"Period Ending Date"** for which you are requesting data.
- **Background Processing**: Reminders are sent in the background. You will receive an email notification if any errors occur during the bulk sending process.
- **Smart Targeting**: The system automatically determines the best report period to target (usually the current or previous quarter end) if a date is not explicitly specified.

## 2. Advanced KPI Cumulation (Year Period)
The system now automatically generates annual (Year) performance records based on your monthly data.

- **Automatic 'Year' Records**: When a portfolio company has exactly 12 months of 'Actual' data within a single fiscal year, the system will automatically create a **'Year'** period KPI record with the total cumulative value.
- **Fiscal Year Alignment**: The 'Year' and 'YTD' calculations respect your entity's specific financial year start date (e.g., April 1st).
- **Progressive YTD**: Year-to-Date (YTD) records now reflect the progress at each monthly interval throughout the fiscal year.

## 3. Data Validation: Future Dates
To maintain data integrity, the system now enforces stricter validation on 'Actual' KPI data.

- **Future Date Prevention**: When uploading a KPI workbook, any data points tagged as **'Actual'** that have a date in the future (relative to the upload time) will be automatically skipped.
- **Budget Data**: This restriction does **not** apply to 'Budget' or 'Forecast' tags, which are expected to have future dates.

## 4. Enhanced Reminder Emails
The notification emails sent to portfolio companies have been improved for better clarity:
- **Call-to-Action**: Emails now feature a clear button to **"Fill KPI Report"**.
- **Formatted Dates**: Reporting periods are now clearly formatted using standard date localizations.
