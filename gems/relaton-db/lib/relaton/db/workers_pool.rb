# frozen_string_literal: true

module Relaton
  class Db
    # Workers poll.
    class WorkersPool
      def initialize(workers = 2, &)
        @queue = SizedQueue.new(workers * 2)
        @threads = Array.new workers do
          Thread.new do
            while item = @queue.pop; yield(item) end
          end
        end
      end

      def <<(item)
        @queue << item
        self
      end
    end
  end
end
