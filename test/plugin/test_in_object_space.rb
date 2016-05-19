require_relative '../helper'
require 'fluent/test'
require 'fluent/plugin/in_object_space'

require 'timeout'

class ObjectSpaceInputTest < Test::Unit::TestCase
  def waiting(seconds, instance)
    begin
      Timeout.timeout(seconds) do
        yield
      end
    rescue Timeout::Error
      STDERR.print(*instance.log.out.logs)
      raise
    end
  end

  class FailObject
    def self.class
      raise "error"
    end
  end

  def setup
    Fluent::Test.setup
  end

  TESTCONFIG = %[
    emit_interval 1
    tag t1
    top 2
  ]

  def create_driver(conf=TESTCONFIG)
    Fluent::Test::InputTestDriver.new(Fluent::ObjectSpaceInput).configure(conf)
  end

  def test_configure
    d = create_driver
    assert_equal 1, d.instance.emit_interval
    assert_equal "t1", d.instance.tag
    assert_equal 2, d.instance.top
  end

  def test_emit
    d = create_driver

    d.run do
      waiting(10, d.instance) do
        sleep 0.5 until d.emit_streams.size > 3
      end
    end

    emits = d.emits
    assert{ emits.length > 0 }

    emits.each { |tag, time, record|
      assert_equal d.instance.tag, tag
      assert_equal d.instance.top, record.keys.size
      assert(time.is_a?(Fluent::EventTime))
    }
  end

  def test_emit_2
    d = create_driver

    d.run do
      waiting(20, d.instance) do
        sleep 0.5 until d.emit_streams.size > 3
      end
    end

    emits = d.emits
    assert{ emits.length > 0 }

    emits.each { |tag, time, record|
      assert_equal d.instance.tag, tag
      assert_equal d.instance.top, record.keys.size
      assert(time.is_a?(Fluent::EventTime))
    }
  end

  def test_emit_3
    d = create_driver

    d.run do
      waiting(30, d.instance) do
        sleep 0.5 until d.emit_streams.size > 3
      end
    end

    emits = d.emits
    assert{ emits.length > 0 }

    emits.each { |tag, time, record|
      assert_equal d.instance.tag, tag
      assert_equal d.instance.top, record.keys.size
      assert(time.is_a?(Fluent::EventTime))
    }
  end

  def test_emit_1b
    d = create_driver

    d.run do
      waiting(10, d.instance) do
        sleep 0.5 until d.emit_streams.size > 3
      end
    end

    emits = d.emits
    assert{ emits.length > 0 }

    emits.each { |tag, time, record|
      assert_equal d.instance.tag, tag
      assert_equal d.instance.top, record.keys.size
      assert(time.is_a?(Fluent::EventTime))
    }
  end

  def test_emit_2b
    d = create_driver

    d.run do
      waiting(20, d.instance) do
        sleep 0.5 until d.emit_streams.size > 3
      end
    end

    emits = d.emits
    assert{ emits.length > 0 }

    emits.each { |tag, time, record|
      assert_equal d.instance.tag, tag
      assert_equal d.instance.top, record.keys.size
      assert(time.is_a?(Fluent::EventTime))
    }
  end

  def test_emit_3b
    d = create_driver

    d.run do
      waiting(30, d.instance) do
        sleep 0.5 until d.emit_streams.size > 3
      end
    end

    emits = d.emits
    assert{ emits.length > 0 }

    emits.each { |tag, time, record|
      assert_equal d.instance.tag, tag
      assert_equal d.instance.top, record.keys.size
      assert(time.is_a?(Fluent::EventTime))
    }
  end
end
