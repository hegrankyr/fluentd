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
  require 'fluent/config/error'
  require 'fluent/config/element'

  module Config
    def self.read(path, new_config = false)
      if new_config
        require 'fluent/config/new_parser'
        NewParser.read(path)
      else
        require 'fluent/config/parser'
        Parser.read(path)
      end
    end

    def self.parse(str, fname, basepath = Dir.pwd, new_config = false)
      if new_config
        require 'fluent/config/new_parser'
        NewParser.parse(str, fname, basepath, Kernel.binding)
      else
        require 'fluent/config/parser'
        Parser.parse(str, fname, basepath)
      end
    end

    def self.new(name='')
      Element.new('', '', {}, [])
    end

    def self.size_value(str)
      case str.to_s
      when /([0-9]+)k/i
        $~[1].to_i * 1024
      when /([0-9]+)m/i
        $~[1].to_i * (1024**2)
      when /([0-9]+)g/i
        $~[1].to_i * (1024**3)
      when /([0-9]+)t/i
        $~[1].to_i * (1024**4)
      else
        str.to_i
      end
    end

    def self.time_value(str)
      case str.to_s
      when /([0-9]+)s/
        $~[1].to_i
      when /([0-9]+)m/
        $~[1].to_i * 60
      when /([0-9]+)h/
        $~[1].to_i * 60*60
      when /([0-9]+)d/
        $~[1].to_i * 24*60*60
      else
        str.to_f
      end
    end

    def self.bool_value(str)
      case str.to_s
      when 'true', 'yes'
        true
      when 'false', 'no'
        false
      else
        nil
      end
    end
  end

  require 'fluent/configurable'

  module PluginId
    def configure(conf)
      @id = conf['id']
      super
    end

    def require_id
      unless @id
        raise ConfigError, "'id' parameter is required"
      end
      @id
    end

    def plugin_id
      @id ? @id : "object:#{object_id.to_s(16)}"
    end
  end
end
