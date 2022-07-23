namespace :irm do
  require "faker"
  require 'digest/sha1'
  require 'factory_bot'
  Chewy.strategy(:atomic)

  desc "generates fake Entity for testing"
  task generateFakeEntities: :environment do
    startup_names = Rails.env == "development" ? ["Urban Company"] : ["Urban Company", "Demo Startup", "Wakefit"]#, "PayTm", "Apna", "RazorPay", "Delhivery"]
    startup_names.each do |name|
      e = FactoryBot.create(:entity, entity_type: "Startup", name: name)
      puts "Entity #{e.name}"
      (1..2).each do |j|
        user = FactoryBot.create(:user, entity: e, first_name: "Emp#{j}")
        puts user.to_json
      end
    end

    wm_names = ["Ambit", "Citi"]
    wm_names.each do |name|
      e = FactoryBot.create(:entity, entity_type: "Advisor", name: name)
      puts "Entity #{e.name}"
      (1..2).each do |j|
        user = FactoryBot.create(:user, entity: e, first_name: "Emp#{j}")
        puts user.to_json
      end
    end

    fund_names = ["IAN"]
    fund_names.each do |name|
      e = FactoryBot.create(:entity, entity_type: "Investment Fund", name: name)
      puts "Entity #{e.name}"
      (1..2).each do |j|
        user = FactoryBot.create(:user, entity: e, first_name: "FM#{j}")
        puts user.to_json
      end
    end


    vc_names = ["Sequoia Capital", "Accel", "Blume Ventures", "Tiger Global Management", "Kalaari Capital"] 
                # "Drip Ventures", "Matrix Partners", "Nexus Venture Partners", "Indian Angel Network", "Omidyar Network India"]
    vc_names.each do |name|
      e = FactoryBot.create(:entity, entity_type: "VC", name: name)
      puts "Entity #{e.name}"
      (1..2).each do |j|
        user = FactoryBot.create(:user, entity: e, first_name: "Emp#{j}")
        puts user.to_json
      end
    end

    user = FactoryBot.create(:user, entity: nil, first_name: "Super", last_name: "Admin", email: "admin@altx.com", curr_role: :super)
    user.add_role(:super)
  rescue Exception => e
    puts e.backtrace.join("\n")
    raise e
  end


  desc "generates fake Blank Entity for testing"
  task generateFakeBlankEntities: :environment do
    # startup_names = ["Demo-Startup"]
    # startup_names.each do |name|
    #   e = FactoryBot.create(:entity, entity_type: "Startup", name: name)
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


    vc_names = ["Demo-VC"] 

    vc_names.each do |name|
      e = FactoryBot.create(:entity, entity_type: "VC", name: name)
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

    Entity.startups.each do |e|
      i = nil
      
      round = FactoryBot.create(:funding_round, entity: e)
      Entity.vcs.each do |vc|
        inv = FactoryBot.create(:investor, entity: e, investor_entity: vc, tag_list: [tags.sample, tags.sample].join(","))
        puts "Investor #{inv.id}"
        inv.investor_entity.employees.each do |user|
          InvestorAccess.create!(investor:inv, user: user, first_name: user.first_name, last_name: user.last_name,  email: user.email, approved: rand(2), entity_id: inv.entity_id)
        end
      end
    end

    Entity.funds.each do |e|
      i = nil
      
      round = FactoryBot.create(:funding_round, entity: e)
      Entity.vcs.each do |vc|
        inv = FactoryBot.create(:investor, entity: e, investor_entity: vc, tag_list: [tags.sample, tags.sample].join(","))
        puts "Investor #{inv.id}"
        inv.investor_entity.employees.each do |user|
          InvestorAccess.create!(investor:inv, user: user, first_name: user.first_name, last_name: user.last_name,  email: user.email, approved: rand(2), entity_id: inv.entity_id)
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
          i = FactoryBot.build(:investment, entity: e, investor: inv, investment_instrument: instrument, funding_round: round, notes: "generateFakeInvestments")
          i = SaveInvestment.call(investment: i).investment
          puts "Investment #{i.to_json}"
        end
      end
    
      5.times do
        inv = e.investors.sample
        AccessRight.create(owner: e, access_type: "Investment", metadata: "All",
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

        deal.start_deal if rand(2).positive?
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
            first_name: h.user&.first_name, last_name: h.user&.last_name)

          offer.quantity = offer.allowed_quantity
          offer.approved = rand(4) > 0
          offer.save
          puts offer.to_json

          offer.approved = true
          offer.save
        end
      end

      sale.reload
      Entity.advisors.each do | advisor |
        qty = ((sale.total_offered_quantity / 100) - rand(10))*100
        price = rand(2) > 0 ? sale.min_price : sale.max_price
        short_listed = rand(4) > 0
        escrow_deposited = rand(2) > 0
        interest = Interest.create(entity_id: sale.entity_id, 
            interest_entity_id: advisor.id, secondary_sale: sale,
            quantity: qty, price: price, user_id: advisor.employees.first.id, 
            short_listed: short_listed, escrow_deposited: escrow_deposited)
        
        puts interest.to_json
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
        FactoryBot.create(:user, entity: e, email: "startup#{i}@gmail.com")
        i += 1
      end
    end
  rescue Exception => e
    puts e.backtrace.join("\n")
    raise e
  end


  task :generateAll => [:generateFakeEntities, :generateFakeInvestors, :generateFakeInvestments, :generateFakeDeals, :generateFakeValuations,:generateFakeHoldings, :generateFakeDocuments, :generateFakeNotes, :generateFakeSales, :generateFakeOffers, :generateFakeBlankEntities] do
    puts "Generating all Fake Data"
    Sidekiq.redis(&:flushdb)
  end

end
