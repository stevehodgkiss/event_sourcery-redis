module EventSourcery
  module Redis
    class Tracker
      DEFAULT_HASH_NAME = :tracker

      def initialize(redis, hash_name: DEFAULT_HASH_NAME)
        @redis = redis
        @hash_name = DEFAULT_HASH_NAME
      end

      def setup(processor_name = nil)
        if processor_name
          redis.hsetnx(hash_name, processor_name, 0)
        end
      end

      def processed_event(processor_name, event_id)
        lock_name = "lock_#{processor_name}"
        redis.watch lock_name
        redis.multi do |multi|
          multi.incr lock_name
          multi.hset(hash_name, processor_name, event_id)
        end
        true
      end

      def reset_last_processed_event_id(processor_name)
        redis.hset(hash_name, processor_name, 0)
      end

      def last_processed_event_id(processor_name)
        redis.hget(hash_name, processor_name).to_i
      end

      def tracked_processors
        redis.hkeys(hash_name)
      end

      private

      attr_reader :redis, :hash_name
    end
  end
end
