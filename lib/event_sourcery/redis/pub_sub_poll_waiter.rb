module EventSourcery
  module Redis
    class PubSubPollWaiter
      def initialize(redis)
        @redis = redis
      end

      def poll(on_subscribe: proc {}, &block)
        catch(:stop) do
          redis.subscribe('new_event') do |on|
            on.subscribe do |_, _|
              on_subscribe.call
            end
            on.message do |channel, message|
              block.call
            end
          end
        end
      end

      private

      attr_reader :redis
    end
  end
end
