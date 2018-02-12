require 'spec_helper'

RSpec.describe InfluxDB::Rails do
  before do
    InfluxDB::Rails.configure do |config|
      config.rails_app_name = 'my-rails-app'
      config.ignored_environments = []
      config.time_precision = "ms"
    end
  end

  describe '.handle_action_controller_metrics' do
    let(:start)   { Time.at(1517567368) }
    let(:finish)  { Time.at(1517567370) }
    let(:payload) { { view_runtime: 2, db_runtime: 2, controller: 'MyController', action: 'show' } }
    let(:data)    {
      {
        values: {
          value: 2
        },
        tags: {
          method: 'MyController#show',
          server: Socket.gethostname,
          app_name: 'my-rails-app'
        },
        timestamp: 1517567370000
      }
    }

    context 'rails_app_name is set' do
      it 'sends metrics with taggings and timestamps' do
        expect_any_instance_of(InfluxDB::Client).to receive(:write_point).with(
          'rails.controller', data.merge({ values: { value: 2000}})
        )
        expect_any_instance_of(InfluxDB::Client).to receive(:write_point).with('rails.view', data)
        expect_any_instance_of(InfluxDB::Client).to receive(:write_point).with('rails.db', data)

        described_class.handle_action_controller_metrics('unused', start, finish, 'unused', payload)
      end
    end

    context 'rails_app_name is nil' do
      before do
        InfluxDB::Rails.configure do |config|
          config.rails_app_name = nil
        end
      end

      it 'doesn not add the app_name tag to metrics' do
        tags = { method: 'MyController#show', server: Socket.gethostname }

        expect_any_instance_of(InfluxDB::Client).to receive(:write_point).with(
          'rails.controller', data.merge({ values: { value: 2000}, tags: tags })
        )
        expect_any_instance_of(InfluxDB::Client).to receive(:write_point).with('rails.view', data.merge(tags: tags))
        expect_any_instance_of(InfluxDB::Client).to receive(:write_point).with('rails.db', data.merge(tags: tags))

        described_class.handle_action_controller_metrics('unused', start, finish, 'unused', payload)
      end
    end
  end

  describe '.convert_timestamp' do
    let(:sometime) { Time.parse('2017-12-11 16:20:29.111222333 UTC') }
    let(:configuration) { double("Configuration") }
    before { allow(InfluxDB::Rails).to receive(:configuration).and_return configuration }

    {
      "ns"  => 1513009229111222272,
      nil   => 1513009229111222272,
      "u"   => 1513009229111222,
      "ms"  => 1513009229111,
      "s"   => 1513009229,
      "m"   => 25216820,
      "h"   => 420280,
    }.each do |precision, converted_value|
      it "should return the timestamp in nanoseconds when precision is #{precision.inspect}" do
        allow(configuration).to receive(:time_precision).and_return(precision)
        expect(InfluxDB::Rails.convert_timestamp(sometime)).to eq(converted_value)
      end
    end

    it "should raise an excpetion when precision is unrecognized" do
      allow(configuration).to receive(:time_precision).and_return('whatever')
      expect{InfluxDB::Rails.convert_timestamp(sometime)}.
        to raise_exception /invalid time precision.*whatever/i
    end
  end

  describe '.current_timestamp' do
    it "should return the current timestamp in the configured precision" do
      now = Time.parse('2017-12-11 16:20:29.111222333 UTC')
      allow(Time).to receive(:now).and_return(now)
      InfluxDB::Rails.configure {|config| config.time_precision = 'ms'}
      expect(InfluxDB::Rails.current_timestamp).to eq(1513009229111)
    end
  end

  describe ".ignorable_exception?" do
    it "should be true for exception types specified in the configuration" do
      class DummyException < Exception; end
      exception = DummyException.new

      InfluxDB::Rails.configure do |config|
        config.ignored_exceptions << 'DummyException'
      end

      expect(InfluxDB::Rails.ignorable_exception?(exception)).to be_truthy
    end

    it "should be true for exception types specified in the configuration" do
      exception = ActionController::RoutingError.new("foo")
      expect(InfluxDB::Rails.ignorable_exception?(exception)).to be_truthy
    end

    it "should be false for valid exceptions" do
      exception = ZeroDivisionError.new
      expect(InfluxDB::Rails.ignorable_exception?(exception)).to be_falsey
    end
  end

  describe 'rescue' do
    it "should transmit an exception when passed" do
      expect(InfluxDB::Rails.client).to receive(:write_point)

      InfluxDB::Rails.rescue do
        raise ArgumentError.new('wrong')
      end
    end

    it "should also raise the exception when in an ignored environment" do
      InfluxDB::Rails.configure do |config|
        config.ignored_environments = %w{development test}
      end

      expect {
        InfluxDB::Rails.rescue do
          raise ArgumentError.new('wrong')
        end
      }.to raise_error(ArgumentError)
    end
  end

  describe "rescue_and_reraise" do
    it "should transmit an exception when passed" do
      expect(InfluxDB::Rails.client).to receive(:write_point)

      expect {
        InfluxDB::Rails.rescue_and_reraise { raise ArgumentError.new('wrong') }
      }.to raise_error(ArgumentError)
    end
  end
end
