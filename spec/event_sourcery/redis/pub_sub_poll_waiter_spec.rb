RSpec.describe EventSourcery::Redis::PubSubPollWaiter do
  let(:waiter) { described_class.new($redis) }
  subject(:event_store) { EventSourcery::Redis::EventStore.new(new_redis_connection) }

  def new_redis_connection
    Redis.connect(port: ENV['BOXEN_REDIS_PORT'] || 6379)
  end

  it 'calls the block on new events' do
    Timeout.timeout(5) do
      waiter.poll(on_subscribe: proc { event_store.sink(new_event) }) do
        puts "Called"
        @called = true
        throw :stop
      end
    end
    expect(@called).to eq true
  end
end
