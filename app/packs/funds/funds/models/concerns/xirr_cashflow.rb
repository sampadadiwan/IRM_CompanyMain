require 'active_support/configurable'
require 'active_support/concern'

    # Expands [Array] to store a set of transactions which will be used to calculate the XIRR
    # @note A Cashflow should consist of at least two transactions, one positive and one negative.
    class XirrCashflow < Array

      PERIOD = 365.25
      FALLBACK = true
        

      attr_reader :raise_exception, :fallback, :iteration_limit, :options
  
      # @param args [Transaction]
      # @example Creating a Cashflow
      #   cf = Cashflow.new
      #   cf << Transaction.new( 1000, date: '2013-01-01'.to_date)
      #   cf << Transaction.new(-1234, date: '2013-03-31'.to_date)
      #   Or
      #   cf = Cashflow.new Transaction.new( 1000, date: '2013-01-01'.to_date), Transaction.new(-1234, date: '2013-03-31'.to_date)
      def initialize(flow: [], period: PERIOD, ** options)
        @period   = period
        @fallback = options[:fallback] || FALLBACK
        @options  = options
        self << flow
        self.flatten!
      end
  
      # Check if Cashflow is invalid
      # @return [Boolean]
      def invalid?
        inflow.empty? || outflows.empty?
      end
  
      # Inverse of #invalid?
      # @return [Boolean]
      def valid?
        !invalid?
      end
  
      # @return [Float]
      # Sums all amounts in a cashflow
      def sum
        self.map(&:amount).sum
      end
  
      # Last investment date
      # @return [Time]
      def max_date
        @max_date ||= self.map(&:date).max
      end
  
      
      def compact_cf
        # self
        compact = Hash.new 0
        self.each { |flow| compact[flow.date] += flow.amount }
        XirrCashflow.new flow: compact.map { |key, value| XirrTransaction.new(value, date: key) }, options: options, period: period
      end
  
      # First investment date
      # @return [Time]
      def min_date
        @min_date ||= self.map(&:date).min
      end
  
      # @return [String]
      # Error message depending on the missing transaction
      def invalid_message
        return 'No positive transaction' if inflow.empty?
        return 'No negative transaction' if outflows.empty?
      end
  
      def period
        @temporary_period || @period
      end
  
      def << arg
        super arg
        self.sort! { |x, y| x.date <=> y.date }
        self
      end
  
      private
  
      
      # @api private
      # Counts how many years from first to last transaction in the cashflow
      # @return
      def periods_of_investment
        (max_date - min_date) / period
      end
  
      
    end
  
  