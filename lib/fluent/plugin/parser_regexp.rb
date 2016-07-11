module Fluent
  module Plugin
    class RegexpParser < Parser
      include Fluent::Compat::TypeConverter

      Plugin.register_parser("regexp", self)

      config_param :expression, :string, default: ""
      config_param :time_key, :string, default: 'time'
      config_param :time_format, :string, default: nil

      def initialize
        super
        @mutex = Mutex.new
      end

      def configure(conf)
        super
        @time_parser = TimeParser.new(@time_format)
        unless @expression.empty?
          if @expression[0] == "/" && @expression[-1] == "/"
            @regexp = Regexp.new(@expression[1..-2])
          else
            raise Fluent::ConfigError, "expression must start with `/` and end with `/`: #{@expression}"
          end
        end
      end

      def parse(text)
        m = @regexp.match(text)
        unless m
          yield nil, nil
          return
        end

        time = nil
        record = {}

        m.names.each do |name|
          if value = m[name]
            if name == @time_key
              time = @mutex.synchronize { @time_parser.parse(value) }
              if @keep_time_key
                record[name] = if @type_converters.nil?
                                 value
                               else
                                 convert_type(name, value)
                               end
              end
            else
              record[name] = if @type_converters.nil?
                               value
                             else
                               convert_type(name, value)
                             end
            end
          end
        end

        if @estimate_current_event
          time ||= Fluent::EventTime.now
        end

        yield time, record
      end
    end
  end
end
