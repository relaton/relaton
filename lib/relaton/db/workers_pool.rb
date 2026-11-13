# frozen_string_literal: true

module Relaton
  class Db
    # Workers poll.
    class WorkersPool
      def initialize(workers = 2, &)
        @queue = SizedQueue.new(workers * 2)
        @threads = Array.new workers do
          Thread.new do
            # A worker that dies silently wedges the pool: the item it was
            # processing never completes, and every consumer blocked on that
            # completion blocks forever (metanorma-standoc CI deadlock,
            # 2026-11-13). The pool outlives any single item's failure.
            while item = @queue.pop
              begin
                yield(item)
              rescue Exception => e # rubocop:disable Lint/RescueException
                Util.error "fetch worker item failed: #{e.class}: #{e.message}"
              end
            end
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
