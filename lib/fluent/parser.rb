#
# Fluent
#
# Copyright (C) 2011 FURUHASHI Sadayuki
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#
module Fluent


class TextParser
  class RegexpParser
    def initialize(regexp, time_format)
      @regexp = regexp
      @time_format = time_format
    end

    attr_accessor :time_format

    def call(text)
      m = @regexp.match(text)
      unless m
        $log.debug "pattern not match: #{text}"
        # TODO?
        return nil, nil
      end

      time = nil
      record = {}

      m.names.each {|name|
        if value = m[name]
          case name
          when "time"
            if @time_format
              time = Time.strptime(value, @time_format).to_i
            else
              time = Time.parse(value).to_i
            end
          else
            record[name] = value
          end
        end
      }

      time ||= Engine.now

      return time, record
    end
  end

  class JSONParser
    include Configurable

    config_param :time_key, :string, :default => 'time'
    config_param :time_format, :string, :default => nil

    def call(text)
      record = Yajl.load(text)

      if value = record.delete(@time_key)
        if @time_format
          time = Time.strptime(value, @time_format).to_i
        else
          time = value.to_i
        end
      else
        time = Engine.now
      end

      return time, record
    end
  end

  TEMPLATES = {
    'apache' => RegexpParser.new(/^(?<host>[^ ]*) [^ ]* (?<user>[^ ]*) \[(?<time>[^\]]*)\] "(?<method>\S+)(?: +(?<path>[^ ]*) +\S*)?" (?<code>[^ ]*) (?<size>[^ ]*)(?: "(?<referer>[^\"]*)" "(?<agent>[^\"]*)")?$/, "%d/%b/%Y:%H:%M:%S %z"),
    'syslog' => RegexpParser.new(/^(?<time>[^ ]*\s*[^ ]* [^ ]*) (?<host>[^ ]*) (?<ident>[a-zA-Z0-9_\/\.\-]*)(?:\[(?<pid>[0-9]+)\])?[^\:]*\: *(?<message>.*)$/, "%b %d %H:%M:%S"),
    'json' => JSONParser.new,
  }

  def self.register_template(name, regexp_or_proc, time_format=nil)
    if regexp_or_proc.is_a?(Regexp)
      pr = regexp_or_proc
    else
      regexp = regexp_or_proc
      pr = RegexpParser.new(regexp, time_format)
    end

    TEMPLATES[name] = pr
  end

  def initialize
    @proc = nil
  end

  def configure(conf, required=true)
    if format = conf['format']
      if format[0] == ?/ && format[format.length-1] == ?/
        # regexp
        begin
          regexp = Regexp.new(format[1..-2])
          if regexp.named_captures.empty?
            raise "No named captures"
          end
        rescue
          raise ConfigError, "Invalid regexp '#{format[1..-2]}': #{$!}"
        end

        time_format = conf['time_format']
        if time_format
          unless regexp.names.include?('time')
            raise ConfigError, "'time_format' parameter is invalid when format doesn't have 'time' capture"
          end
        end

        @proc = RegexpParser.new(regexp, time_format)

      else
        # built-in template
        @proc = TEMPLATES[format]
        unless @proc
          raise ConfigError, "Unknown format template '#{format}'"
        end

        if @proc.respond_to?(:configure)
          @proc.configure(conf)
        end

      end

    else
      return nil if !required
      raise ConfigError, "'format' parameter is required"
    end

    return true
  end

  def parse(text)
    return @proc.call(text)
  end
end


end
