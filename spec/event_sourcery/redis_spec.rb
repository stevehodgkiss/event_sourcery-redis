require 'spec_helper'

describe EventSourcery::Redis do
  it 'has a version number' do
    expect(EventSourcery::Redis::VERSION).not_to be nil
  end
end
