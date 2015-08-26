require_relative '../helper'
require 'timecop'
require 'fluent/plugin/filter_record_transformer'

class RecordTransformerFilterTest < Test::Unit::TestCase
  include Fluent

  setup do
    Test.setup
    @hostname = Socket.gethostname.chomp
    @tag = 'test.tag'
    @tag_parts = @tag.split('.')
    @time = Time.utc(1,2,3,4,5,2010,nil,nil,nil,nil)
    Timecop.freeze(@time)
  end

  teardown do
    Timecop.return
  end

  def create_driver(conf = '')
    Test::FilterTestDriver.new(RecordTransformerFilter, @tag).configure(conf, true)
  end

  sub_test_case 'configure' do
    test 'check default' do
      assert_nothing_raised do
        create_driver
      end
    end

    test "keep_keys must be specified together with renew_record true" do
      assert_raise(Fluent::ConfigError) do
        create_driver(%[keep_keys a])
      end
    end
  end

  sub_test_case "test options" do
    def emit(config, msgs = [''])
      d = create_driver(config)
      d.run {
        msgs.each { |msg|
          d.emit({'foo' => 'bar', 'message' => msg}, @time)
        }
      }.filtered
    end

    CONFIG = %[
      <record>
        hostname ${hostname}
        tag ${tag}
        time ${time}
        message ${hostname} ${tag_parts[-1]} ${message}
      </record>
    ]

    test 'typical usage' do
      msgs = ['1', '2']
      es = emit(CONFIG, msgs)
      es.each_with_index do |(t, r), i|
        assert_equal('bar', r['foo'])
        assert_equal(@hostname, r['hostname'])
        assert_equal(@tag, r['tag'])
        assert_equal(@time.to_s, r['time'])
        assert_equal("#{@hostname} #{@tag_parts[-1]} #{msgs[i]}", r['message'])
      end
    end

    test 'remove_keys' do
      config = CONFIG + %[remove_keys foo,message]
      es = emit(config)
      es.each_with_index do |(t, r), i|
        assert_not_include(r, 'foo')
        assert_equal(@hostname, r['hostname'])
        assert_equal(@tag, r['tag'])
        assert_equal(@time.to_s, r['time'])
        assert_not_include(r, 'message')
      end
    end

    test 'renew_record' do
      config = CONFIG + %[renew_record true]
      msgs = ['1', '2']
      es = emit(config, msgs)
      es.each_with_index do |(t, r), i|
        assert_not_include(r, 'foo')
        assert_equal(@hostname, r['hostname'])
        assert_equal(@tag, r['tag'])
        assert_equal(@time.to_s, r['time'])
        assert_equal("#{@hostname} #{@tag_parts[-1]} #{msgs[i]}", r['message'])
      end
    end

    test 'renew_time_key' do
      config = %[renew_time_key message]
      times = [ Time.local(2,2,3,4,5,2010,nil,nil,nil,nil), Time.local(3,2,3,4,5,2010,nil,nil,nil,nil) ]
      msgs = times.map{|t| t.to_f.to_s }
      es = emit(config, msgs)
      es.each_with_index do |(time, record), i|
        assert_equal(times[i].to_i, time)
        assert(time.is_a?(Fluent::EventTime))
      end
    end

    test 'keep_keys' do
      config = %[renew_record true\nkeep_keys foo,message]
      msgs = ['1', '2']
      es = emit(config, msgs)
      es.each_with_index do |(t, r), i|
        assert_equal('bar', r['foo'])
        assert_equal(msgs[i], r['message'])
      end
    end

    test 'enable_ruby' do
      config = %[
        enable_ruby yes
        <record>
          message ${hostname} ${tag_parts.last} ${URI.encode(message)}
        </record>
      ]
      msgs = ['1', '2']
      es = emit(config, msgs)
      es.each_with_index do |(t, r), i|
        assert_equal("#{@hostname} #{@tag_parts[-1]} #{msgs[i]}", r['message'])
      end
    end

    test 'hash_value' do
      config = %[
        <record>
          hash_field {"k1":100, "k2":"foobar"}
        </record>
      %]
      msgs = ['1', '2']
      es = emit(config, msgs)
      es.each_with_index do |(t, r), i|
        assert_equal({"k1"=>100, "k2"=>"foobar"}, r['hash_field'])
      end
    end

    test 'array_value' do
      config = %[
        <record>
          array_field [1, 2, 3]
        </record>
      %]
      msgs = ['1', '2']
      es = emit(config, msgs)
      es.each_with_index do |(t, r), i|
        assert_equal([1,2,3], r['array_field'])
      end
    end

    test 'array_hash_mixed' do
      config = %[
        <record>
          mixed_field {"hello":[1,2,3], "world":{"foo":"bar"}}
        </record>
      %]
      msgs = ['1', '2']
      es = emit(config, msgs)
      es.each_with_index do |(t, r), i|
        assert_equal({"hello"=>[1,2,3], "world"=>{"foo"=>"bar"}}, r['mixed_field'])
      end
    end
  end

  sub_test_case 'test placeholders' do
    def emit(config, msgs = [''])
      d = create_driver(config)
      yield d if block_given?
      d.run {
        msgs.each do |msg|
          record = {
            'eventType0' => 'bar',
            'message'    => msg,
          }
          record = record.merge(msg) if msg.is_a?(Hash)
          d.emit(record, @time)
        end
      }.filtered
    end

    %w[yes no].each do |enable_ruby|
      test "hostname with enble_ruby #{enable_ruby}" do
        config = %[
          enable_ruby #{enable_ruby}
          <record>
            message ${hostname}
          </record>
        ]
        es = emit(config)
        es.each do |t, r|
          assert_equal(@hostname, r['message'])
        end
      end

      test "tag with enable_ruby #{enable_ruby}" do
        config = %[
          enable_ruby #{enable_ruby}
          <record>
            message ${tag}
          </record>
        ]
        es = emit(config)
        es.each do |t, r|
          assert_equal(@tag, r['message'])
        end
      end

      test "tag_parts with enable_ruby #{enable_ruby}" do
        config = %[
          enable_ruby #{enable_ruby}
          <record>
            message ${tag_parts[0]} ${tag_parts[-1]}
          </record>
        ]
        expected = "#{@tag.split('.').first} #{@tag.split('.').last}"
        es = emit(config)
        es.each do |t, r|
          assert_equal(expected, r['message'])
        end
      end

      test "${tag_prefix[N]} and ${tag_suffix[N]} with enable_ruby #{enable_ruby}" do
        config = %[
          enable_ruby #{enable_ruby}
          <record>
            message ${tag_prefix[1]} ${tag_prefix[-2]} ${tag_suffix[2]} ${tag_suffix[-3]}
          </record>
        ]
        @tag = 'prefix.test.tag.suffix'
        expected = "prefix.test prefix.test.tag tag.suffix test.tag.suffix"
        es = emit(config)
        es.each do |t, r|
          assert_equal(expected, r['message'])
        end
      end

      test "time with enable_ruby #{enable_ruby}" do
        config = %[
          enable_ruby #{enable_ruby}
          <record>
            message ${time}
          </record>
        ]
        es = emit(config)
        es.each do |t, r|
          assert_equal(@time.to_s, r['message'])
        end
      end

      test "record keys with enable_ruby #{enable_ruby}" do
        config = %[
          enable_ruby #{enable_ruby}
          remove_keys eventType0
          <record>
            message bar ${message}
            eventtype ${eventType0}
          </record>
        ]
        msgs = ['1', '2']
        es = emit(config, msgs)
        es.each_with_index do |(t, r), i|
          assert_not_include(r, 'eventType0')
          assert_equal("bar", r['eventtype'])
          assert_equal("bar #{msgs[i]}", r['message'])
        end
      end

      test "hash values with placeholders with enable_ruby #{enable_ruby}" do
        config = %[
          enable_ruby #{enable_ruby}
          <record>
            hash_field {
              "hostname":"${hostname}",
              "tag":"${tag}",
              "${tag}":100
            }
          </record>
        ]
        msgs = ['1', '2']
        es = emit(config, msgs)
        es.each_with_index do |(t, r), i|
          assert_equal({"hostname" => @hostname, "tag" => @tag, "#{@tag}" => 100}, r['hash_field'])
        end
      end

      test "array values with placeholders with enable_ruby #{enable_ruby}" do
        config = %[
          enable_ruby #{enable_ruby}
          <record>
            array_field ["${hostname}", "${tag}"]
          </record>
        ]
        msgs = ['1', '2']
        es = emit(config, msgs)
        es.each_with_index do |(t, r), i|
          assert_equal([@hostname, @tag], r['array_field'])
        end
      end

      test "array and hash values with placeholders with enable_ruby #{enable_ruby}" do
        config = %[
          enable_ruby #{enable_ruby}
          <record>
            mixed_field [{"tag":"${tag}"}]
          </record>
        ]
        msgs = ['1', '2']
        es = emit(config, msgs)
        es.each_with_index do |(t, r), i|
          assert_equal([{"tag" => @tag}], r['mixed_field'])
        end
      end

      test "keys with placeholders with enable_ruby #{enable_ruby}" do
        config = %[
          enable_ruby #{enable_ruby}
          renew_record true
          <record>
            ${hostname} hostname
            foo.${tag}  tag
          </record>
        ]
        msgs = ['1', '2']
        es = emit(config, msgs)
        es.each_with_index do |(t, r), i|
          assert_equal({@hostname=>'hostname',"foo.#{@tag}"=>'tag'}, r)
        end
      end

      test "disabled typecasting of values with enable_ruby #{enable_ruby}" do
        config = %[
          auto_typecast false
          enable_ruby #{enable_ruby}
          <record>
            single      ${source}
            multiple    ${source}${source}
            with_prefix prefix-${source}
            with_suffix ${source}-suffix
          </record>
        ]
        msgs = [
          { "source" => "string" },
          { "source" => 123 },
          { "source" => [1, 2] },
          { "source" => {a:1, b:2} },
          { "source" => nil },
        ]
        expected_results = [
          { :single      => "string",
            :multiple    => "stringstring",
            :with_prefix => "prefix-string",
            :with_suffix => "string-suffix" },
          { :single      => 123.to_s,
            :multiple    => "#{123.to_s}#{123.to_s}",
            :with_prefix => "prefix-#{123.to_s}",
            :with_suffix => "#{123.to_s}-suffix" },
          { :single      => [1, 2].to_s,
            :multiple    => "#{[1, 2].to_s}#{[1, 2].to_s}",
            :with_prefix => "prefix-#{[1, 2].to_s}",
            :with_suffix => "#{[1, 2].to_s}-suffix" },
          { :single      => {a:1, b:2}.to_s,
            :multiple    => "#{{a:1, b:2}.to_s}#{{a:1, b:2}.to_s}",
            :with_prefix => "prefix-#{{a:1, b:2}.to_s}",
            :with_suffix => "#{{a:1, b:2}.to_s}-suffix" },
          { :single      => nil.to_s,
            :multiple    => "#{nil.to_s}#{nil.to_s}",
            :with_prefix => "prefix-#{nil.to_s}",
            :with_suffix => "#{nil.to_s}-suffix" },
        ]
        actual_results = []
        es = emit(config, msgs)
        es.each_with_index do |(t, r), i|
          actual_results << {
            :single      => r["single"],
            :multiple    => r["multiple"],
            :with_prefix => r["with_prefix"],
            :with_suffix => r["with_suffix"],
          }
        end
        assert_equal(expected_results, actual_results)
      end

      test "enabled typecasting of values with enable_ruby #{enable_ruby}" do
        config = %[
          auto_typecast yes
          enable_ruby #{enable_ruby}
          <record>
            single      ${source}
            multiple    ${source}${source}
            with_prefix prefix-${source}
            with_suffix ${source}-suffix
          </record>
        ]
        msgs = [
          { "source" => "string" },
          { "source" => 123 },
          { "source" => [1, 2] },
          { "source" => {a:1, b:2} },
          { "source" => nil },
        ]
        expected_results = [
          { :single      => "string",
            :multiple    => "stringstring",
            :with_prefix => "prefix-string",
            :with_suffix => "string-suffix" },
          { :single      => 123,
            :multiple    => "#{123.to_s}#{123.to_s}",
            :with_prefix => "prefix-#{123.to_s}",
            :with_suffix => "#{123.to_s}-suffix" },
          { :single      => [1, 2],
            :multiple    => "#{[1, 2].to_s}#{[1, 2].to_s}",
            :with_prefix => "prefix-#{[1, 2].to_s}",
            :with_suffix => "#{[1, 2].to_s}-suffix" },
          { :single      => {a:1, b:2},
            :multiple    => "#{{a:1, b:2}.to_s}#{{a:1, b:2}.to_s}",
            :with_prefix => "prefix-#{{a:1, b:2}.to_s}",
            :with_suffix => "#{{a:1, b:2}.to_s}-suffix" },
          { :single      => nil,
            :multiple    => "#{nil.to_s}#{nil.to_s}",
            :with_prefix => "prefix-#{nil.to_s}",
            :with_suffix => "#{nil.to_s}-suffix" },
        ]
        actual_results = []
        es = emit(config, msgs)
        es.each_with_index do |(t, r), i|
          actual_results << {
            :single      => r["single"],
            :multiple    => r["multiple"],
            :with_prefix => r["with_prefix"],
            :with_suffix => r["with_suffix"],
          }
        end
        assert_equal(expected_results, actual_results)
      end
    end

    test 'unknown placeholder (enable_ruby no)' do
      config = %[
        enable_ruby no
        <record>
          message ${unknown}
        </record>
      ]
      emit(config) { |d|
        mock(d.instance.log).warn("unknown placeholder `${unknown}` found")
      }
    end

    test 'failed to expand (enable_ruby yes)' do
      config = %[
        enable_ruby yes
        <record>
          message ${unknown['bar']}
        </record>
      ]
      es = emit(config) { |d|
        mock(d.instance.log).warn("failed to expand `${unknown['bar']}`", anything)
      }
      es.each do |t, r|
        assert_nil(r['message'])
      end
    end

    test 'expand fields starting with @ (enable_ruby no)' do
      config = %[
        enable_ruby no
        <record>
          foo ${@timestamp}
        </record>
      ]
      d = create_driver(config)
      message = {"@timestamp" => "foo"}
      es = d.run { d.emit(message, @time) }.filtered
      es.each do |t, r|
        assert_equal(message["@timestamp"], r['foo'])
      end
    end

    test 'expand fields starting with @ (enable_ruby yes)' do
      config = %[
        enable_ruby yes
        <record>
          foo ${__send__("@timestamp")}
        </record>
      ]
      d = create_driver(config)
      message = {"@timestamp" => "foo"}
      es = d.run { d.emit(message, @time) }.filtered
      es.each do |t, r|
        assert_equal(message["@timestamp"], r['foo'])
      end
    end
  end
end
