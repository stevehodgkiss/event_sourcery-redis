RSpec.describe EventSourcery::Redis::Tracker do
  subject(:tracker) { described_class.new($redis) }
  let(:hash_name) { described_class::DEFAULT_HASH_NAME }
  let(:processor_name) { 'blah' }
  let(:track_entry) { table.where(name: processor_name).first }

  def last_processed_event_id
    tracker.last_processed_event_id(processor_name)
  end

  describe '#setup' do
    before do
      $redis.del(hash_name)
    end

    context 'auto create projector tracker enabled' do
      it 'creates the table' do
        tracker.setup(processor_name)
        expect($redis.hget(hash_name, processor_name)).to eq "0"
      end

      it "creates an entry for the projector if it doesn't exist" do
        tracker.setup(processor_name)
        expect(last_processed_event_id).to eq 0
      end
    end
  end

  describe '#processed_event' do
    it 'updates the tracker entry to the given ID' do
      tracker.processed_event(processor_name, 1)
      expect(last_processed_event_id).to eq 1
    end
  end

  describe '#last_processed_event_id' do
    it 'starts at 0' do
      expect(last_processed_event_id).to eq 0
    end

    it 'updates as events are processed' do
      tracker.processed_event(processor_name, 1)
      expect(last_processed_event_id).to eq 1
    end
  end

  describe '#reset_last_processed_event_id' do
    it 'resets the last processed event back to 0' do
      tracker.processed_event(processor_name, 1)
      tracker.reset_last_processed_event_id(processor_name)
      expect(last_processed_event_id).to eq 0
    end
  end

  describe '#tracked_processors' do
    before do
      tracker.setup
    end

    context 'with two tracked processors' do
      before do
        tracker.setup(:one)
        tracker.setup(:two)
      end

      it 'returns an array of tracked processors' do
        expect(tracker.tracked_processors).to eq ['one', 'two']
      end
    end

    context 'with no tracked processors' do
      it 'returns an empty array' do
        expect(tracker.tracked_processors).to eq []
      end
    end
  end
end
