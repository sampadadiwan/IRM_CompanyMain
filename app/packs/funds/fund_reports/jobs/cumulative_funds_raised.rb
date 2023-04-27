class CumulativeFundsRaised
    def generate_report(fund_id, report_date)
        puts "CumulativeFundsRaised: Generating Report for #{fund_id}, #{report_date} "

        @fund = Fund.find(fund_id)
        @report_date = report_date
        
        @fund_report = FundReport.new(name: "CumulativeFundsRaised", fund: @fund, entity_id: @fund.entity_id, report_date: @report_date)
        

        @fund_report.data = Hash.new
        @fund_report.data["Total Corpus As On Date"] = @fund.collected_amount.to_d

        @fund_report.save
    end
end