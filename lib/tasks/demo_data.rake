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
        inv = FactoryBot.build(:investor, entity: e, investor_entity: vc, tag_list: [tags.sample, tags.sample].join(","), pan: vc.pan)
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

          kyc = FactoryBot.build(:investor_kyc, entity: e, investor: inv)
          kyc.save(validate: false)
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
        CreateOptionPool.wtf?(option_pool: pool).success?.should == true
        ApproveOptionPool.wtf?(option_pool: pool).success?.should == true
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
      
          CreateHolding.call(holding: holding)
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
        CreateDeal.wtf?(deal: deal)
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
    
      sale = FactoryBot.create(:secondary_sale, entity:e, start_date:Date.today, end_date:Date.today + 100.days)
      puts sale.to_json

    end
  rescue Exception => e
    puts e.backtrace.join("\n")
    raise e
  end

  desc "generates fake Offers for testing"
  task generateFakeOffers: :environment do
    SecondarySale.all.active.each do |sale|

      next if !sale.active 
      next if sale.offers.any?
      
      sale.entity.investors.not_holding.sample(3).each do |inv|

        if inv.investor_entity.employees.empty?
          user = FactoryBot.create(:user, entity: inv.investor_entity)
        else
          user = inv.investor_entity.employees.sample
        end

        AccessRight.create(owner: sale, access_type: "SecondarySale", entity: sale.entity, investor: inv, metadata: "Seller")

        
        offer = FactoryBot.build(:offer, secondary_sale: sale, 
          user:, investor: inv, entity: sale.entity,
          full_name: user&.full_name)

        offer.quantity = rand(10)*100
        offer.approved = rand(4) > 0
        # offer.signature = File.open("public/sample_uploads/signature.png", "rb")
        offer.properties = {"city": ["Bangalore", "Mumbai", "Chennai", "Delhi"][rand(4)], "domicile": ["India", "Foreign"][rand(2)], "dp_name": ["NSDL", "CDSL"][rand(2)] }  
        offer.save
        puts offer.to_json

        offer.approved = true
        offer.save!
        
      end

      sale.reload
      sale.entity.investors.not_holding.sample(5).each do | investor |
        
          if investor.investor_entity.employees.empty?
            FactoryBot.create(:user, entity: investor.investor_entity)
          end

          (1..80).each do
            qty = ((sale.total_offered_quantity / 100) - rand(10))*100
            qty = qty > 0 ? qty : sale.total_offered_quantity
            
            price = rand(2) > 0 ? sale.min_price : sale.max_price
            short_listed = rand(4) > 0
            escrow_deposited = rand(2) > 0
            interest = FactoryBot.build(:interest, entity_id: sale.entity_id, 
                investor_id: investor.id, secondary_sale: sale,
                quantity: qty, price: price, user_id: investor.investor_entity.employees.sample.id, 
                short_listed_status: Interest::STATUSES.sample, escrow_deposited: escrow_deposited)
            
            # interest.signature = File.open("public/sample_uploads/signature2.png", "rb")
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

  
  desc "generates fake portfolios"
  task generateFakePortfolios: :environment do

    startup_names = ["PayTm", "Apna", "RazorPay", "Delhivery", "Eat Fit", "Cult Fit", "Quadrant"]
    startup_names.each do |name|
      
      startup = FactoryBot.build(:entity, entity_type: "Company", name: name)
      startup.save!
      ap startup

      # (1..2).each do |j|
      #   user = FactoryBot.create(:user, entity: startup, first_name: "Emp#{j}")
      #   user.add_role :company_admin
      #   user.add_role :approver
      #   puts user.to_json
      # end
    end

    Entity.funds.each do |e|
      startup_names.each do |name|        
        begin
          investor_entity = Entity.find_by(name: name)
          pc = FactoryBot.build(:investor, entity: e, investor_entity: investor_entity, investor_name: name, pan: investor_entity.pan, category: "Portfolio Company")
          pc.save!
          FactoryBot.create(:valuation, entity: e, owner: pc)         
        rescue Exception => e
          puts e.message
        end
      end
    end

    Fund.all.each do |fund|
      # Generate Buys
      (1..4).each do
        begin
          pc = fund.entity.investors.portfolio_companies.sample
          pi = FactoryBot.build(:portfolio_investment, entity: fund.entity, fund:, portfolio_company: pc, quantity: 100 * rand(1..10))
          PortfolioInvestmentCreate.call(portfolio_investment: pi)
          puts "Creating PI #{pi} for #{fund.name}"
        rescue Exception => e
          puts e.message
        end
      end

      (1..2).each do
        # Generate Sells
        begin
          pc = fund.entity.investors.portfolio_companies.sample
          pi = FactoryBot.build(:portfolio_investment, entity: fund.entity, fund:, portfolio_company: pc, quantity: -100 * rand(1..4))
          PortfolioInvestmentCreate.call(portfolio_investment: pi)
          puts "Creating PI #{pi} for #{fund.name}"
        rescue Exception => e
          puts e.message
        end
      end
    end

  end

  desc "generates fake funds"
  task generateFakeFunds: :environment do
    i = 1
    files = ["holdings.xlsx", "signature.png", "investor_access.xlsx", "Offer_1_SPA.pdf"]
    
    
    Entity.funds.each do |e|
      3.times do
        fund = FactoryBot.build(:fund, entity: e)

        if fund.save
          puts "Creating fund #{fund.name} for #{e.name}"
          doc = Document.create!(entity: e, owner: fund, name: Faker::Company.catch_phrase, 
                  text: Faker::Company.catch_phrase, user: e.employees.sample,
                  file: File.new("public/sample_uploads/#{files[rand(4)]}", "r"))


          e.investors.sample(5).each do |inv|
            AccessRight.create!(owner: fund, access_type: "Fund", entity: e, investor: inv, metadata: "Investor")
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

              if rand(2) > 0
                cr.update(verified: true)
                FundUnitsJob.perform_now(cr.capital_call_id, "CapitalCall", "For Call", 1)
              end

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
        end # if fund.save

      end

      sleep(3)
    end
  rescue Exception => e
    puts e.backtrace.join("\n")
    raise e
  end

  task :generateAll => [:generateFakeEntities, :generateFakeInvestors, :generateFakeDocuments, :generateFakeNotes, :generateFakeSales, :generateFakeOffers, :generateFakeFunds, :generateFakePortfolios] do
    puts "Generating all Fake Data"
  end

  desc "Seeds two fully-populated demo deals for DealManagementAgent testing. " \
       "Idempotent — tears down and recreates only the two demo deals by name. " \
       "Usage: rake 'irm:seed_demo_deals[ENTITY_ID]'"
  task :seed_demo_deals, [:entity_id] => :environment do |_, args|
    require "faker"

    entity_id = args[:entity_id].to_i
    abort "Usage: rake 'irm:seed_demo_deals[ENTITY_ID]'" if entity_id.zero?

    entity = Entity.find_by(id: entity_id) || abort("Entity #{entity_id} not found")
    admin  = entity.employees.first
    abort "No employees for entity #{entity_id}" if admin.nil?

    puts "[deal_demo] Entity: #{entity.name} (id=#{entity_id}), admin=#{admin.email}"

    demo_deals = [
      "Series B — Horizon Analytics (Demo)",
      "Seed Round — NovaTech Ventures (Demo)"
    ]

    deal_steps = [
      ["Info Deck Sent",                   5],
      ["NDA Executed",                    10],
      ["Management Presentation",         20],
      ["Financial Due Diligence",         35],
      ["Legal Due Diligence",             50],
      ["Term Sheet Issued",               60],
      ["Term Sheet Countersigned",        70],
      ["Board Approval",                  80],
      ["Definitive Docs (SHA/SSA/SPA)",   90],
      ["Remittance & Closing",           100],
    ]

    log = ->(msg) { puts "[deal_demo] #{msg}" }

    sample_file = ->(filename) {
      path = Rails.root.join("public/sample_uploads/#{filename}")
      abort "Sample file not found: #{path}" unless File.exist?(path)
      File.open(path, "r")
    }

    attach_doc = ->(owner:, name:, filename:, folder: nil) {
      doc = Document.new(entity: entity, owner: owner, name: name, user: admin, send_email: false)
      doc.folder = folder || owner.document_folder
      doc.file   = sample_file.call(filename)
      doc.save!
      log.call("    doc '#{name}' → #{owner.class}##{owner.id}")
      doc
    rescue StandardError => e
      log.call("    WARN: could not attach '#{name}': #{e.message}")
      nil
    }

    create_activity_templates = ->(deal) {
      deal.deal_activities.where(deal_investor_id: nil).destroy_all
      deal_steps.each_with_index do |(title, days), idx|
        DealActivity.create!(
          deal:             deal,
          deal_investor_id: nil,
          entity:           entity,
          status:           "Template",
          title:            title,
          sequence:         idx + 1,
          days:             days
        )
      end
      log.call("  #{deal_steps.size} activity templates created")
    }

    create_investor = ->(deal:, investor:, status:, amount:, tier:, lead:, source:, tags:, notes:) {
      di = DealInvestor.new(
        deal:                      deal,
        investor:                  investor,
        entity:                    entity,
        status:                    status,
        primary_amount_cents:      amount,
        pre_money_valuation_cents: 200_000_000_00,
        tier:                      tier,
        deal_lead:                 lead,
        source:                    source,
        tags:                      tags
      )
      di.save!
      di.notes = notes
      di.save!
      di.create_activities
      di.reload
      log.call("  DealInvestor##{di.id} #{investor.investor_name} [#{status}] — #{di.deal_activities.count} activities")
      di
    }

    complete_steps = ->(di, deal, titles) {
      titles.each do |title|
        act = di.deal_activities.find_by(title: title)
        next unless act
        act.update!(status: "Complete", by_date: deal.start_date + act.days)
        log.call("    ✓ #{title}")
      end
    }

    set_by_dates = ->(di, deal) {
      di.deal_activities.where.not(status: %w[Complete complete]).each do |act|
        act.update!(by_date: deal.start_date + act.days)
      end
    }

    backdate_stagnant = ->(di, days) {
      DealInvestor.where(id: di.id).update_all(updated_at: days.days.ago)
      DealActivity.where(deal_investor_id: di.id).update_all(updated_at: days.days.ago)
      log.call("  Backdated #{di.investor_name} (stagnant: #{days}d)")
    }

    make_overdue = ->(di, title, days_ago) {
      act = di.deal_activities.find_by(title: title)
      return unless act
      act.update!(status: "Incomplete", by_date: days_ago.days.ago.to_date)
      log.call("    ⚠ #{title} overdue by #{days_ago}d")
    }

    make_upcoming = ->(di, title, days_from_now) {
      act = di.deal_activities.find_by(title: title)
      return unless act
      act.update!(status: "Incomplete", by_date: days_from_now.days.from_now.to_date)
      log.call("    ⏰ #{title} due in #{days_from_now}d")
    }

    Chewy.strategy(:bypass) do

      # Tear down previous demo runs
      demo_deals.each do |deal_name|
        Deal.unscoped.where(entity_id: entity_id, name: deal_name).each do |d|
          log.call("Destroying existing deal '#{d.name}' (id=#{d.id})")
          d.deal_investors.each(&:destroy!)
          d.destroy!
        end
      end

      # Need at least 7 investors (4 for deal 1 + 3 for deal 2)
      available_investors = entity.investors
                                  .not_portfolio_companies
                                  .not_advisors
                                  .not_rms
                                  .limit(20)
                                  .to_a
      abort "Need ≥7 LP/VC investors in entity #{entity_id} — found #{available_investors.size}" if available_investors.size < 7

      # ── Deal 1: Series B ───────────────────────────────────────────────────────
      log.call("\n═══ Deal 1: Series B — Horizon Analytics ═══")

      deal1 = Deal.new(
        entity:       entity,
        name:         demo_deals[0],
        status:       "Open",
        amount_cents: 50_000_000_00,
        currency:     "USD",
        start_date:   90.days.ago.to_date,
        end_date:     60.days.from_now.to_date,
        tags:         "SaaS,B2B,Series B",
        units:        "shares"
      )
      CreateDeal.wtf?(deal: deal1)
      abort "CreateDeal failed: #{deal1.errors.full_messages.join(', ')}" unless deal1.persisted?
      log.call("Created Deal##{deal1.id}: #{deal1.name}")

      create_activity_templates.call(deal1)

      data_room1 = deal1.deal_documents_folder
      [
        ["Information Memorandum",  "Offer_1_SPA.pdf"                    ],
        ["Financial Model",         "CashFlow.xlsx"                       ],
        ["Cap Table",               "CRISIL Report.xlsx"                  ],
        ["NDA Template",            "Mutual-Confidentiality-Agreement.docx"],
        ["Draft Term Sheet",        "SPA.docx"                           ],
      ].each { |(name, file)| attach_doc.call(owner: deal1, name: name, filename: file, folder: data_room1) }

      inv1a, inv1b, inv1c, inv1d = available_investors[0..3]

      log.call("\n  Investor A — Active & Progressing")
      di1a = create_investor.call(
        deal: deal1, investor: inv1a, status: "Active", amount: 10_000_000_00, tier: "Lead",
        lead: "Priya Sharma", source: "Warm Intro", tags: "strategic,lead",
        notes: "Anchor investor. Very engaged — attended all management presentations. " \
               "Key concern: board seat composition. Positive on the product roadmap. " \
               "Committed to term sheet by end of quarter."
      )
      complete_steps.call(di1a, deal1, ["Info Deck Sent", "NDA Executed", "Management Presentation"])
      set_by_dates.call(di1a, deal1)
      attach_doc.call(owner: di1a, name: "Horizon NDA Signed",       filename: "Mutual-Confidentiality-Agreement.docx")
      attach_doc.call(owner: di1a, name: "Horizon Term Sheet Draft", filename: "SPA.docx")
      attach_doc.call(owner: di1a, name: "Horizon Financial Model",  filename: "CashFlow.xlsx")
      mgmt_act1a = di1a.deal_activities.find_by(title: "Management Presentation")
      attach_doc.call(owner: mgmt_act1a, name: "Mgmt Pres Deck", filename: "Offer_1_SPA.pdf") if mgmt_act1a

      log.call("\n  Investor B — Stagnant & Overdue")
      di1b = create_investor.call(
        deal: deal1, investor: inv1b, status: "Active", amount: 5_000_000_00, tier: "Follow-on",
        lead: "Karan Mehta", source: "Cold Outreach", tags: "at-risk",
        notes: "Has not responded to last two emails. Last contact was 3 weeks ago after " \
               "the management presentation. Possible concerns about burn rate. " \
               "Need to schedule follow-up call urgently."
      )
      complete_steps.call(di1b, deal1, ["Info Deck Sent"])
      set_by_dates.call(di1b, deal1)
      make_overdue.call(di1b, "NDA Executed",           14)
      make_overdue.call(di1b, "Management Presentation", 5)
      backdate_stagnant.call(di1b, 20)
      attach_doc.call(owner: di1b, name: "Vertex NDA Signed", filename: "Mutual-Confidentiality-Agreement.docx")

      log.call("\n  Investor C — Upcoming Due Dates")
      di1c = create_investor.call(
        deal: deal1, investor: inv1c, status: "Pending", amount: 8_000_000_00, tier: "Co-investor",
        lead: "Ananya Rao", source: "LP Network", tags: "family-office,co-invest",
        notes: "In diligence phase. Scheduled a call with their IC next week. " \
               "Expects draft SHA by end of month. Supportive on valuation. " \
               "Wants to understand exit mechanics before committing."
      )
      complete_steps.call(di1c, deal1, ["Info Deck Sent", "NDA Executed"])
      set_by_dates.call(di1c, deal1)
      make_upcoming.call(di1c, "Financial Due Diligence", 2)
      make_upcoming.call(di1c, "Term Sheet Issued",        6)
      attach_doc.call(owner: di1c, name: "Bansal NDA Executed",     filename: "Mutual-Confidentiality-Agreement.docx")
      attach_doc.call(owner: di1c, name: "Bansal Diligence Report", filename: "CRISIL Report.xlsx")

      log.call("\n  Investor D — Declined")
      di1d = create_investor.call(
        deal: deal1, investor: inv1d, status: "Declined", amount: 2_000_000_00, tier: "Minority",
        lead: "Priya Sharma", source: "Conference", tags: "declined",
        notes: "Passed due to allocation constraints for the quarter. May revisit in Series C."
      )
      complete_steps.call(di1d, deal1, ["Info Deck Sent"])
      set_by_dates.call(di1d, deal1)

      # ── Deal 2: Seed Round ─────────────────────────────────────────────────────
      log.call("\n═══ Deal 2: Seed Round — NovaTech Ventures ═══")

      deal2 = Deal.new(
        entity:       entity,
        name:         demo_deals[1],
        status:       "Open",
        amount_cents: 5_000_000_00,
        currency:     "USD",
        start_date:   45.days.ago.to_date,
        end_date:     90.days.from_now.to_date,
        tags:         "DeepTech,AI,Seed",
        units:        "shares"
      )
      CreateDeal.wtf?(deal: deal2)
      abort "CreateDeal failed: #{deal2.errors.full_messages.join(', ')}" unless deal2.persisted?
      log.call("Created Deal##{deal2.id}: #{deal2.name}")

      create_activity_templates.call(deal2)

      data_room2 = deal2.deal_documents_folder
      [
        ["Pitch Deck",              "Offer_1_SPA.pdf"],
        ["Financial Projections",   "CashFlow.xlsx"  ],
        ["SAFE Agreement Draft",    "SPA.docx"       ],
      ].each { |(name, file)| attach_doc.call(owner: deal2, name: name, filename: file, folder: data_room2) }

      inv2a, inv2b, inv2c = available_investors[4..6]

      log.call("\n  Investor E — Active & Progressing")
      di2a = create_investor.call(
        deal: deal2, investor: inv2a, status: "Active", amount: 2_000_000_00, tier: "Lead",
        lead: "Vikram Nair", source: "Angel Network", tags: "strategic,deep-tech",
        notes: "Very bullish on the AI angle. Has invested in 3 similar seed rounds this year. " \
               "Wants co-investor rights on Series A. Quick decision-maker — expects term sheet in 2 weeks."
      )
      complete_steps.call(di2a, deal2, ["Info Deck Sent", "NDA Executed"])
      set_by_dates.call(di2a, deal2)
      attach_doc.call(owner: di2a, name: "NovaTech NDA Signed",  filename: "Mutual-Confidentiality-Agreement.docx")
      attach_doc.call(owner: di2a, name: "Investment Memo Draft", filename: "SPA.docx")

      log.call("\n  Investor F — Overdue NDA")
      di2b = create_investor.call(
        deal: deal2, investor: inv2b, status: "Active", amount: 1_500_000_00, tier: "Co-investor",
        lead: "Siddharth Rao", source: "Referral", tags: "fintech-focused",
        notes: "Interested but slow on legal. NDA was supposed to be signed last week. " \
               "Their counsel requested minor changes to confidentiality clause."
      )
      complete_steps.call(di2b, deal2, ["Info Deck Sent"])
      set_by_dates.call(di2b, deal2)
      make_overdue.call(di2b, "NDA Executed", 7)
      attach_doc.call(owner: di2b, name: "Redlined NDA", filename: "Mutual-Confidentiality-Agreement.docx")

      log.call("\n  Investor G — Declined")
      di2c = create_investor.call(
        deal: deal2, investor: inv2c, status: "Declined", amount: 500_000_00, tier: "Minority",
        lead: "Vikram Nair", source: "Cold Outreach", tags: "declined",
        notes: "Ticket size too small for their fund mandate. Suggested two other funds to approach."
      )
      complete_steps.call(di2c, deal2, ["Info Deck Sent"])
      set_by_dates.call(di2c, deal2)

      # ── Summary ────────────────────────────────────────────────────────────────
      log.call("\n════════════════════════════════════════════")
      log.call("Demo deals seeded for entity #{entity_id}")
      log.call("════════════════════════════════════════════")

      [deal1, deal2].each do |deal|
        deal.reload
        log.call("\n#{deal.name} (Deal##{deal.id})")
        log.call("  Status: #{deal.status}  |  Data room: #{deal.deal_documents_folder.documents.count} docs")
        deal.deal_investors.includes(:deal_activities).each do |di|
          log.call("  [#{di.status.ljust(9)}] #{di.investor_name.ljust(42)} " \
                   "| #{di.deal_activities.count} activities " \
                   "| #{Document.where(owner_type: 'DealInvestor', owner_id: di.id).count} docs " \
                   "| stagnant=#{di.stagnant?}")
        end
      end

      agent = SupportAgent.find_by(entity_id: entity_id, agent_type: "DealManagementAgent")
      if agent
        log.call("\n── Agent ready ─────────────────────────────────────────────────────────")
        log.call("SupportAgent##{agent.id} DealManagementAgent (enabled=#{agent.enabled})")
        log.call("")
        log.call("Run against Deal 1:")
        log.call("  DealManagementAgent.wtf?(support_agent_id: #{agent.id}, target: Deal.find(#{deal1.id}))")
        log.call("")
        log.call("Run against Deal 2:")
        log.call("  DealManagementAgent.wtf?(support_agent_id: #{agent.id}, target: Deal.find(#{deal2.id}))")
      else
        log.call("\nWARN: DealManagementAgent not found for entity #{entity_id}.")
        log.call("Run first:  rake 'support_agents:setup[#{entity_id}]'")
      end

    end # Chewy.strategy(:bypass)
  end

end
