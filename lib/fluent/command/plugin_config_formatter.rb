#
# Fluentd
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

require "erb"
require "optparse"
require "fluent/plugin"
require "fluent/env"
require "fluent/engine"
require "fluent/system_config"
require "fluent/config/element"

class FluentPluginConfigFormatter

  AVAILABLE_FORMATS = [:txt, :markdown, :json]

  def initialize(argv = ARGV)
    @argv = argv

    @compact = false
    @format = :markdown
    @verbose = false
    @libs = []
    @plugin_dirs = []
    @options = {}

    prepare_option_parser
  end

  def call
    parse_options!
    init_engine
    @plugin = Fluent::Plugin.__send__("new_#{@plugin_type}", @plugin_name)
    @plugin_helpers = @plugin.class.plugin_helpers
    __send__("dump_#{@format}")
  end

  private

  def dump_txt
    puts "helpers: #{@plugin_helpers.join(',')}"
    dump_body
  end

  def dump_markdown
    helpers = "### Plugin_helpers\n\n"
    @plugin_helpers.each do |helper|
      helpers << "* #{helper}\n"
    end
    puts "#{helpers}\n"
    dump_body
  end

  def dump_body
    @plugin.class.ancestors.reverse_each do |plugin_class|
      next unless plugin_class.respond_to?(:dump)
      next if plugin_class == Fluent::Plugin::Base
      unless @verbose
        next if plugin_class.name =~ /::PluginHelper::/
      end
      puts plugin_class.name if @verbose
      puts plugin_class.dump(0, @options)
    end
  end

  def dump_json
    dumped_config = {}
    dumped_config[:plugin_helpers] = @plugin_helpers
    @plugin.class.ancestors.reverse_each do |plugin_class|
      next unless plugin_class.respond_to?(:dump)
      next if plugin_class == Fluent::Plugin::Base
      unless @verbose
        next if plugin_class.name =~ /::PluginHelper::/
      end
      dumped_config[plugin_class.name] = plugin_class.dump(0, @options)
    end
    puts dumped_config.to_json
  end

  def usage(message = nil)
    puts @paser.to_s
    puts "Error: #{message}" if message
    exit(false)
  end

  def prepare_option_parser
    @parser = OptionParser.new
    @parser.banner = <<BANNER
Usage: #{$0} [options] <type> <name>
BANNER
    @parser.on("--verbose", "Be verbose") do
      @verbose = true
    end
    @parser.on("-c", "--compact", "Compact output") do
      @compact = true
    end
    @parser.on("-f", "--format=FORMAT", "Specify format") do |s|
      @format = s.to_sym
    end
    @parser.on("-r NAME", "Add library path") do |s|
      @libs << s
    end
    @parser.on("-p", "--plugin=DIR", "Add plugin directory") do |s|
      @plugin_dirs << s
    end
  end

  def parse_options!
    @parser.parse!(@argv)

    raise "Must specify plugin type and name" unless @argv.size == 2

    @plugin_type, @plugin_name = @argv
    @options = {
      compact: @compact,
      format: @format,
      verbose: @verbose,
    }
  rescue => e
    usage(e)
  end

  def init_engine
    system_config = Fluent::SystemConfig.new
    Fluent::Engine.init(system_config)

    @libs.each do |lib|
      require lib
    end

    @plugin_dirs.each do |dir|
      if Dir.exist?(dir)
        dir = File.expand_path(dir)
        Fluent::Engine.add_plugin_dir(dir)
      end
    end
  end
end
