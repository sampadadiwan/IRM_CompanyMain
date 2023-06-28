namespace :irm do
  require "faker"
  require 'digest/sha1'
  require 'factory_bot'
  Chewy.strategy(:atomic)

  desc "generates fake Entity for testing"
  task generateFakeEntities: :environment do
    startup_names = Rails.env == "development" ? ["Urban Company"] : ["Urban Company", "Demo Company", "Wakefit"]#, "PayTm", "Apna", "RazorPay", "Delhivery"]
    startup_names.each do |name|
      e = FactoryBot.create(:entity, entity_type: "Company", name: name)
      puts "Entity #{e.name}"
      (1..2).each do |j|
        user = FactoryBot.create(:user, entity: e, first_name: "Emp#{j}")
        user.add_role :company_admin
        user.add_role :approver
        puts user.to_json
      end
    end

    wm_names = ["Ambit", "Citi", "Sauce", "Carpediem", "Justin Capital", "TerraCore", "TerraBits"]
    wm_names.each do |name|
      e = FactoryBot.create(:entity, entity_type: "Investment Advisor", name: name)
      puts "Entity #{e.name}"
      (1..2).each do |j|
        user = FactoryBot.create(:user, entity: e, first_name: "Emp#{j}")
        puts user.to_json
      end
    end

    fund_names = ["IAN", "Atrium Angels"]
    fund_names.each do |name|
      e = FactoryBot.create(:entity, entity_type: "Investment Fund", name: name, enable_funds: true, enable_inv_opportunities: true)
      puts "Entity #{e.name}"
      (1..2).each do |j|
        user = FactoryBot.create(:user, entity: e, first_name: "FM#{j}")
        user.add_role :company_admin
        user.add_role :approver
        puts user.to_json
      end
    end

    cons_names = ["Legal Eagles", "Awesome Accounting"]
    cons_names.each do |name|
      e = FactoryBot.create(:entity, entity_type: "Advisor", name: name)
      puts "Entity #{e.name}"
      (1..2).each do |j|
        user = FactoryBot.create(:user, entity: e, first_name: "Advisor#{j}")
        puts user.to_json
      end
    end


    vc_names = ["Sequoia Capital", "Accel", "Blume Ventures", "Tiger Global Management", "Kalaari Capital"] 
                # "Drip Ventures", "Matrix Partners", "Nexus Venture Partners", "Indian Angel Network", "Omidyar Network India"]
    vc_names.each do |name|
      e = FactoryBot.create(:entity, entity_type: "Investor", name: name)
      puts "Entity #{e.name}"
      (1..2).each do |j|
        user = FactoryBot.create(:user, entity: e, first_name: "Emp#{j}")
        user.add_role :company_admin
        user.add_role :approver
        puts user.to_json
      end
    end


    family_offices = "Waterfield Advisors,Sekhsaria family office,Metta investors,Delta Ventures,Bansal family office,Arun Gupta".split(",") #,Ram Sharma,DSQ,Sync Invest,Tamarind investments,Maheshwari Family Office,Q10 LLP,Mac Invest,Alpha Funds,Rahul Singh,Youwecan,MSD investments,Copter Invest,VK Invest,S10 Ventures".split(",")
    
    family_offices.each do |name|
      e = FactoryBot.create(:entity, entity_type: "Family Office", name: name, enable_funds: true, enable_inv_opportunities: true)
      puts "Entity #{e.name}"
      (1..2).each do |j|
        user = FactoryBot.create(:user, entity: e, first_name: "Emp#{j}")
        puts user.to_json
      end
    end


  investor_advisors = "Hansen Investor Advisors,Juniper Investor Advisors".split(",") 
    
  investor_advisors.each do |name|
      e = FactoryBot.create(:entity, entity_type: "Investor Advisor", name: name, enable_funds: true, enable_inv_opportunities: true)
      puts "Entity #{e.name}"
      (1..2).each do |j|
        user = FactoryBot.create(:user, entity: e, first_name: "Emp#{j}")
        puts user.to_json
      end
    end
    
    entity = FactoryBot.create(:entity, entity_type: "Company")
    user = FactoryBot.create(:user, entity:, first_name: "Super", last_name: "Admin", email: "admin@altx.com", curr_role: :super)
    user.add_role(:super)
  rescue Exception => e
    puts e.backtrace.join("\n")
    raise e
  end


  desc "generates fake Blank Entity for testing"
  task generateFakeBlankEntities: :environment do
    # startup_names = ["Demo-Company"]
    # startup_names.each do |name|
    #   e = FactoryBot.create(:entity, entity_type: "Company", name: name)
    #   puts "Entity #{e.name}"
    #   (1..1).each do |j|
    #     user = FactoryBot.create(:user, entity: e, first_name: "Emp#{j}")
    #     puts user.to_json
    #   end
    # end

    wm_names = ["Demo-Advisor"]
    wm_names.each do |name|
      e = FactoryBot.create(:entity, entity_type: "Advisor", name: name)
      puts "Entity #{e.name}"
      (1..1).each do |j|
        user = FactoryBot.create(:user, entity: e, first_name: "Emp#{j}")
        puts user.to_json
      end
    end


    vc_names = ["Demo-Investor"] 

    vc_names.each do |name|
      e = FactoryBot.create(:entity, entity_type: "Investor", name: name)
      puts "Entity #{e.name}"
      (1..2).each do |j|
        user = FactoryBot.create(:user, entity: e, first_name: "Emp#{j}")
        puts user.to_json
      end
    end

  rescue Exception => e
    puts e.backtrace.join("\n")
    raise e
  end


  desc "generates fake Documents for testing"
  task generateFakeDocuments: :environment do
    dnames = "Fact Sheet,Cap Table,Latest Financials,Conversion Stats,Deal Sheet".split(",")
    files = ["holdings.xlsx", "signature.png", "investor_access.xlsx", "Offer_1_SPA.pdf"]
    begin
      Entity.startups.each do |e|
        folders = ["Finances", "Metrics", "Investor Notes", "Employee ESOPs Docs"]
        root = e.folders.first
        folders.each do |f|
          Folder.create(entity: e, name: f, parent: root)
        end

        e.reload
        folders = ["Q1", "Q2", "Q3", "Q4", "Series A"]
        root = e.folders.where(name: "Finances").first
        folders.each do |f|
          Folder.create(entity: e, name: f, parent: root)
        end


        e.reload
        folders = ["Operational", "Sales", "People", "Tech"]
        root = e.folders.where(name: "Metrics").first
        folders.each do |f|
          Folder.create(entity: e, name: f, parent: root)
        end

        e.reload
        folders = ["Product Demos", "Founder Interviews", "2022 Roadmap"]
        root = e.folders.where(name: "Investor Notes").first
        folders.each do |f|
          Folder.create(entity: e, name: f, parent: root)
        end


        (0..3).each do |i|
          doc = Document.create!(entity: e, name: dnames[i], 
                text: Faker::Company.catch_phrase, user: e.employees.sample,
                folder: e.folders.sample, file: File.new("public/sample_uploads/#{files[i]}", "r"))

          5.times do
            inv = e.investors.sample
            AccessRight.create(owner: doc, access_type: "Document", 
                               entity: e, access_to_category: Investor::INVESTOR_CATEGORIES[rand(Investor::INVESTOR_CATEGORIES.length)])
          end
        end
      end
    rescue Exception => e
      puts e.backtrace.join("\n")
      raise e
    end
  end

  desc "generates fake Investors for testing"
  task generateFakeInvestors: :environment do

    tags = %w[Warm Cold $50m+ $100m+ Secondary]
    files = ["holdings.xlsx", "signature.png", "investor_access.xlsx", "Offer_1_SPA.pdf"]
    

    Entity.startups.each do |e|
      i = nil
      
      round = FactoryBot.create(:funding_round, entity: e)
      Entity.vcs.each do |vc|
        inv = FactoryBot.build(:investor, entity: e, investor_entity: vc, tag_list: [tags.sample, tags.sample].join(","))
        puts "Investor #{inv.entity_id} #{inv.pan}"

        if inv.save!
          doc = Document.create!(entity: inv.entity, owner: inv, name: Faker::Company.catch_phrase, 
                  text: Faker::Company.catch_phrase, user: inv.entity.employees.sample,
                  file: File.new("public/sample_uploads/#{files[rand(4)]}", "r")) if rand(2) > 0

          inv.investor_entity.employees.each do |user|
            InvestorAccess.create!(investor:inv, user: user, first_name: user.first_name, last_name: user.last_name,  email: user.email, approved: rand(2), entity_id: inv.entity_id)
          end
        end
      end
      
    end

    Entity.funds.each do |e|
      i = nil
      
      
      round = FactoryBot.create(:funding_round, entity: e)
      Entity.family_offices.each do |fo|
        inv = FactoryBot.build(:investor, entity: e, investor_entity: fo, tag_list: [tags.sample, tags.sample].join(","))
        puts "Investor #{inv.entity_id} #{inv.pan}"

        if inv.save!
          doc = Document.create!(entity: inv.entity, owner: inv, name: Faker::Company.catch_phrase, 
                  text: Faker::Company.catch_phrase, user: inv.entity.employees.sample,
                  file: File.new("public/sample_uploads/#{files[rand(4)]}", "r")) if rand(2) > 0


          inv.investor_entity.employees.each do |user|
            InvestorAccess.create!(investor:inv, user: user, first_name: user.first_name, last_name: user.last_name,  email: user.email, approved: rand(2), entity_id: inv.entity_id)
          end

          FactoryBot.create(:investor_kyc, entity: e, investor: inv)
        end
      end

      
    end

  rescue Exception => e
    puts e.backtrace.join("\n")
    raise e
  end

  desc "generates fake Investments for testing"
  task generateFakeInvestments: :environment do
    Entity.startups.each do |e|
      i = nil
      round = FactoryBot.create(:funding_round, entity: e)
      Entity.vcs.each do |vc|
        inv = e.investors.not_holding.not_trust.sample
        (1..3).each do
          round = FactoryBot.create(:funding_round, entity: e) if rand(10) < 2 
          instrument = ["Equity", "Preferred"][rand(2)]
          i = FactoryBot.build(:investment, entity: e, investor: inv, investment_instrument: instrument, 
            funding_round: round, notes: "generateFakeInvestments", 
            investment_date: (Date.today - rand(6).years - rand(12).months))
          i = SaveInvestment.call(investment: i).investment
          puts "Investment #{i.to_json}"
        end
      end
    
      5.times do
        inv = e.investors.sample
        AccessRight.create(owner: e, access_type: "Investment", metadata: "Self",
                           entity: e, access_to_category: Investor::INVESTOR_CATEGORIES[rand(Investor::INVESTOR_CATEGORIES.length)])
      end

      InvestmentPercentageHoldingJob.new.perform(e.id)
    end

    # AggregateInvestment.all.each.map(&:update_percentage_holdings)
    
  rescue Exception => e
    puts e.backtrace.join("\n")
    raise e
  end

  desc "generates fake Investments for testing"
  task generateFakeFundInvestments: :environment do
    Entity.funds.each do |e|
      i = nil
      round = e.funding_rounds.sample
      e.investors.each do |inv|
        (1..3).each do
          round = e.funding_rounds.sample
          instrument = "Units"
          i = FactoryBot.build(:investment, entity: e, investor: inv, investment_instrument: instrument, 
            funding_round: round, notes: "generateFakeInvestments", 
            investment_date: (Date.today - rand(6).years - rand(12).months))
          i = SaveInvestment.call(investment: i).investment
          puts "Investment #{i.to_json}"
        end
      end
    
      5.times do
        inv = e.investors.sample
        AccessRight.create(owner: e, access_type: "Investment", metadata: "Self",
                           entity: e, access_to_category: Investor::INVESTOR_CATEGORIES[rand(Investor::INVESTOR_CATEGORIES.length)])
      end

      InvestmentPercentageHoldingJob.new.perform(e.id)
    end

    # AggregateInvestment.all.each.map(&:update_percentage_holdings)
    
  rescue Exception => e
    puts e.backtrace.join("\n")
    raise e
  end


  desc "generates fake Holdings for testing"
  task generateFakeHoldings: :environment do

    Entity.startups.each do |e|
      (1..4).each do |p|
        pool = FactoryBot.build(:option_pool, entity: e, approved: false, name: "Pool #{p}")
        
        uploader = FileUploader.new(:store)
        file = File.new("#{Rails.root}/public/sample_uploads/signature.png")
        uploaded_file = uploader.upload(file)

        pool.certificate_signature_data = uploaded_file.to_json
        pool.save

        (1..4).each do |i|
          # 10 + 20 + 30 + 40
          pool.vesting_schedules << pool.vesting_schedules.build(months_from_grant: i*12, vesting_percent: 10*i, entity_id: e.id)
        end
        pool = CreateOptionPool.call(option_pool: pool).option_pool
        ApproveOptionPool.call(option_pool: pool)
      end
    end

    Investor.holding.each do |investor|
      puts "Holdings for #{investor.to_json}"
      (1..8).each do |j|
        user = User.where(first_name: "Emp#{j}-#{investor.id}").first
        user ||= FactoryBot.create(:user, entity: investor.investor_entity, first_name: "Emp#{j}-#{investor.id}")
        puts user.to_json
        
        InvestorAccess.create!(investor:investor, user: user, first_name: user.first_name, 
              last_name: user.last_name, email: user.email, approved: false, 
              entity_id: investor.entity_id)

      

        (1..3).each do |i|

          investment_instrument = ["Equity", "Preferred", "Options"][rand(3)]
          if investment_instrument == "Options" 
            pool = investor.entity.option_pools.sample 
            funding_round = pool.funding_round
            grant_date = Date.today - rand(36).months
          else 
            pool = nil
            funding_round = investor.entity.funding_rounds.where("funding_rounds.name not like 'Pool%'").sample
            grant_date = nil
          end
    
          holding = Holding.new(user: user, entity: investor.entity, investor_id: investor.id, 
              orig_grant_quantity: (1 + rand(10))*100, price_cents: rand(3..10) * 100000, 
              employee_id: (0...8).map { (65 + rand(26)).chr }.join,
              investment_instrument: investment_instrument, option_pool: pool, grant_date: grant_date,
              holding_type: investor.category, funding_round: funding_round)
      
          holding = CreateHolding.call(holding: holding).holding
        end
      end
    end

    VestedJob.new.perform
    
  rescue Exception => e
    puts e.backtrace.join("\n")
    raise e
  end

  desc "generates fake Notes for testing"
  task generateFakeNotes: :environment do
      (1..100).each do |j|
        note = FactoryBot.create(:note)
      end
  rescue Exception => e
    puts e.backtrace.join("\n")
    raise e
  end


  desc "generates fake Valuations for testing"
  task generateFakeValuations: :environment do
    Entity.startups.each do |e|
      (1..5).each do |j|
        d = Date.today - (5-j).years
        v = FactoryBot.create(:valuation, entity: e, valuation_date: d)
        puts v.to_json
      end
    end
  rescue Exception => e
    puts e.backtrace.join("\n")
    raise e
  end

  desc "generates fake Deals for testing"
  task generateFakeDeals: :environment do
    Entity.startups.each do |e|
      3.times do
        deal = FactoryBot.build(:deal, entity: e)
        deal = CreateDeal.call(deal: deal).deal
        puts "Deal #{deal.id}"
        deal.entity.investors.not_holding.not_trust.each do |inv|
          di = FactoryBot.create(:deal_investor, investor: inv, entity: e, deal: deal)
          puts "DealInvestor #{di.id} for investor #{inv.id}"
          (1..rand(10)).each do
            u = rand(2).positive? ? di.investor.investor_entity.employees.sample : di.investor.entity.employees.sample
            msg = FactoryBot.create(:message, owner: di, entity: e, user: u, investor: di.investor)
          end

          (1..rand(5)).each do
            u = rand(2).positive? ? di.investor.investor_entity.employees.sample : di.investor.entity.employees.sample
            msg = FactoryBot.create(:task, owner: di, entity: e, user: u, 
                                    for_entity_id: di.investor.investor_entity_id)
          end


          AccessRight.create(owner: deal, access_type: "Deal", entity: e, investor: inv)
        end

        # deal.start_deal if rand(2).positive?
      end

    end
  rescue Exception => e
    puts e.backtrace.join("\n")
    raise e
  end

  desc "generates fake Sales for testing"
  task generateFakeSales: :environment do
    Entity.startups.each do |e|
    
      FactoryBot.create(:secondary_sale, entity:e, start_date:Date.today, end_date:Date.today + 10.days)

    end
  rescue Exception => e
    puts e.backtrace.join("\n")
    raise e
  end

  desc "generates fake Offers for testing"
  task generateFakeOffers: :environment do
    SecondarySale.all.each do |sale|

      sale.entity.investors.holding.each do |inv|
        AccessRight.create(owner: sale, access_type: "SecondarySale", entity: sale.entity, investor: inv, metadata: "Seller")
      end
      
      sale.entity.holdings.each do |h|

        if h.user
          puts h.to_json

          offer = FactoryBot.build(:offer, holding:h, secondary_sale: sale, 
            user: h.user, investor: h.investor, entity: h.entity,
            full_name: h.user&.full_name)

          offer.quantity = offer.allowed_quantity
          offer.approved = rand(4) > 0
          offer.signature = File.open("public/sample_uploads/signature.png", "rb")
          offer.properties = {"city": ["Bangalore", "Mumbai", "Chennai", "Delhi"][rand(4)], "domicile": ["India", "Foreign"][rand(2)], "dp_name": ["NSDL", "CDSL"][rand(2)] }  
          offer.save
          puts offer.to_json

          offer.approved = true
          offer.save
        end
      end

      sale.reload
      Entity.investment_advisors.each do | advisor |
        investor = FactoryBot.build(:investor, entity: sale.entity, investor_entity: advisor, investor_name: advisor.name, category: "Investment Advisor")
        
        if investor.save
          qty = ((sale.total_offered_quantity / 100) - rand(10))*100
          price = rand(2) > 0 ? sale.min_price : sale.max_price
          short_listed = rand(4) > 0
          escrow_deposited = rand(2) > 0
          interest = FactoryBot.build(:interest, entity_id: sale.entity_id, 
              investor_id: investor.id, secondary_sale: sale,
              quantity: qty, price: price, user_id: advisor.employees.first.id, 
              short_listed: short_listed, escrow_deposited: escrow_deposited)
          
          interest.signature = File.open("public/sample_uploads/signature2.png", "rb")
          interest.properties = {"city": ["Bangalore", "Mumbai", "Chennai", "Delhi"][rand(4)], "domicile": ["India", "Foreign"][rand(2)], "dp_name": ["NSDL", "CDSL"][rand(2)] }

          interest.save!
          puts interest.to_json
        end

        
      end
      
    end
  rescue Exception => e
    puts e.backtrace.join("\n")
    raise e
  end

  desc "generates fake load testing users"
  task generateFakeLoadTestUsers: :environment do
    i = 1
    Entity.startups.each do |e|
      5.times do
        FactoryBot.create(:user, entity: e, email: "company#{i}@gmail.com")
        i += 1
      end
    end
  rescue Exception => e
    puts e.backtrace.join("\n")
    raise e
  end

  desc "generates fake funds"
  task generateFakeFunds: :environment do
    i = 1
    files = ["holdings.xlsx", "signature.png", "investor_access.xlsx", "Offer_1_SPA.pdf"]
    
    startup_names = ["PayTm", "Apna", "RazorPay", "Delhivery", "Eat Fit", "Cult Fit", "Quadrant"]
    startup_names.each do |name|
      startup = FactoryBot.create(:entity, entity_type: "Company", name: name)
      puts "Entity #{startup.name}"
      (1..2).each do |j|
        user = FactoryBot.create(:user, entity: startup, first_name: "Emp#{j}")
        user.add_role :company_admin
        user.add_role :approver
        puts user.to_json
      end
    end

    Entity.funds.each do |e|
      3.times do
        fund = FactoryBot.create(:fund, entity: e)

        doc = Document.create!(entity: e, owner: fund, name: Faker::Company.catch_phrase, 
                text: Faker::Company.catch_phrase, user: e.employees.sample,
                file: File.new("public/sample_uploads/#{files[rand(4)]}", "r"))


        e.investors.sample(5).each do |inv|
          AccessRight.create(owner: fund, access_type: "Fund", entity: e, investor: inv, metadata: "Investor")
          commitment = FactoryBot.create(:capital_commitment, investor: inv, fund: )
          
          doc = Document.create!(entity: e, owner: commitment, name: Faker::Company.catch_phrase, 
                text: Faker::Company.catch_phrase, user: e.employees.sample,
                file: File.new("public/sample_uploads/#{files[rand(4)]}", "r"))
        end


        (1..3).each do 
          fund.reload
          call = FactoryBot.create(:capital_call, fund: ) 
          doc = Document.create!(entity: e, owner: call, name: Faker::Company.catch_phrase, 
                text: Faker::Company.catch_phrase, user: e.employees.sample,
                file: File.new("public/sample_uploads/#{files[rand(4)]}", "r"))


          CapitalCallJob.perform_now(call.id, "Generate")
          call.capital_remittances.each do |cr|
            doc = Document.create!(entity: e, owner: cr, name: Faker::Company.catch_phrase, 
                text: Faker::Company.catch_phrase, user: e.employees.sample,
                file: File.new("public/sample_uploads/#{files[rand(4)]}", "r")) if rand(2) > 0

            FactoryBot.create(:capital_remittance_payment, capital_remittance: cr, folio_amount_cents: cr.call_amount_cents,  payment_date: cr.capital_call.due_date, fund: cr.fund, entity: cr.entity)

          end
        end

        (1..3).each do 
          fund.reload
          distribution = FactoryBot.create(:capital_distribution, fund: , approved: true, generate_payments_paid: true) 
          doc = Document.create!(entity: e, owner: distribution, name: Faker::Company.catch_phrase, 
                text: Faker::Company.catch_phrase, user: e.employees.sample,
                file: File.new("public/sample_uploads/#{files[rand(4)]}", "r"))


          CapitalDistributionJob.perform_now(distribution.id)
          distribution.capital_distribution_payments.each do |cr|
            doc = Document.create!(entity: e, owner: cr, name: Faker::Company.catch_phrase, 
                text: Faker::Company.catch_phrase, user: e.employees.sample,
                file: File.new("public/sample_uploads/#{files[rand(4)]}", "r")) if rand(2) > 0

          end
        end

        startup_names.each do |name|        
          begin
            pc = FactoryBot.create(:investor, entity: e, investor_name: name, category: "Portfolio Company")
            FactoryBot.create(:valuation, entity: e)
            (1..3).each do
              begin
                FactoryBot.create(:valuation, entity: e, portfolio_company: pc)
                pi = FactoryBot.create(:portfolio_investment, entity: e, fund:, portfolio_company: pc)
              rescue
              end
            end
          rescue
          end
        end

      end

      sleep(3)
    end
  rescue Exception => e
    puts e.backtrace.join("\n")
    raise e
  end

  task :generateAll => [:generateFakeEntities, :generateFakeInvestors, :generateFakeInvestments, :generateFakeDeals, :generateFakeValuations,:generateFakeHoldings, :generateFakeDocuments, :generateFakeNotes, :generateFakeSales, :generateFakeOffers, :generateFakeBlankEntities, :generateFakeFunds] do
    puts "Generating all Fake Data"
    Sidekiq.redis(&:flushdb)
  end

end
