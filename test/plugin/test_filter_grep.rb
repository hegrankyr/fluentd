require 'helper'
require 'fluent/test'
require 'fluent/plugin/filter_grep'

# TODO: Replace with FilterTestDriver
class GrepFilterTest < Test::Unit::TestCase
  setup do
    @filter = Fluent::GrepFilter.new
    @time = Fluent::Engine.now
  end

  def configure(instance, conf, use_v1 = false)
    config = if conf.is_a?(Fluent::Config::Element)
               str
             else
               Fluent::Config.parse(conf, "(test)", "(test_dir)", use_v1)
             end
    instance.configure(config)
    instance
  end

  sub_test_case 'configure' do
    test 'check default' do
      configure(@filter, '')
      assert_empty(@filter.regexps)
      assert_empty(@filter.excludes)
    end

    test "regexpN can contain a space" do
      configure(@filter, %[regexp1 message  foo])
      assert_equal(Regexp.compile(/ foo/), @filter.regexps['message'])
    end

    test "excludeN can contain a space" do
      configure(@filter, %[exclude1 message  foo])
      assert_equal(Regexp.compile(/ foo/), @filter.excludes['message'])
    end
  end

  sub_test_case 'filter_stream' do
    def messages
      [
        "2013/01/13T07:02:11.124202 INFO GET /ping",
        "2013/01/13T07:02:13.232645 WARN POST /auth",
        "2013/01/13T07:02:21.542145 WARN GET /favicon.ico",
        "2013/01/13T07:02:43.632145 WARN POST /login",
      ]
    end

    def emit(config, msgs)
      es = Fluent::MultiEventStream.new
      msgs.each { |msg|
        es.add(@time, {'foo' => 'bar', 'message' => msg})
      }

      configure(@filter, config)
      @filter.filter_stream('filter.test', es);
    end

    test 'empty config' do
      es = emit('', messages)
      assert_equal(4, es.instance_variable_get(:@record_array).size)
    end

    test 'regexpN' do
      es = emit('regexp1 message WARN', messages)
      assert_equal(3, es.instance_variable_get(:@record_array).size)
      assert_block('only WARN logs') do
        es.all? { |t, r|
          !r['message'].include?('INFO')
        }
      end
    end

    test 'excludeN' do
      es = emit('exclude1 message favicon', messages)
      assert_equal(3, es.instance_variable_get(:@record_array).size)
      assert_block('remove favicon logs') do
        es.all? { |t, r|
          !r['message'].include?('favicon')
        }
      end
    end

    sub_test_case 'with invalid sequence' do
      def messages
        [
          "\xff".force_encoding('UTF-8'),
        ]
      end

      test "don't raise an exception" do
        assert_nothing_raised { 
          emit(%[regexp1 message WARN], ["\xff".force_encoding('UTF-8')])
        }
      end
    end
  end

  sub_test_case 'grep non-string jsonable values' do
    def emit(msg, config = 'regexp1 message 0')
      es = Fluent::MultiEventStream.new
      es.add(@time, {'foo' => 'bar', 'message' => msg})

      configure(@filter, config)
      @filter.filter_stream('filter.test', es);
    end

    data(
      'array' => ["0"],
      'hash' => ["0" => "0"],
      'integer' => 0,
      'float' => 0.1)
    test "value" do |data|
      es = emit(data)
      assert_equal(1, es.instance_variable_get(:@record_array).size)
    end

    test "value boolean" do
      es = emit(true, %[regexp1 message true])
      assert_equal(1, es.instance_variable_get(:@record_array).size)
    end
  end
end
