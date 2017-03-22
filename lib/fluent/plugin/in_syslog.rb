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

require 'fluent/plugin/input'
require 'fluent/config/error'
require 'fluent/plugin/parser'

require 'yajl'

module Fluent::Plugin
  class SyslogInput < Input
    Fluent::Plugin.register_input('syslog', self)

    helpers :parser, :compat_parameters, :server

    DEFAULT_PARSER = 'syslog'
    SYSLOG_REGEXP = /^\<([0-9]+)\>(.*)/

    FACILITY_MAP = {
      0   => 'kern',
      1   => 'user',
      2   => 'mail',
      3   => 'daemon',
      4   => 'auth',
      5   => 'syslog',
      6   => 'lpr',
      7   => 'news',
      8   => 'uucp',
      9   => 'cron',
      10  => 'authpriv',
      11  => 'ftp',
      12  => 'ntp',
      13  => 'audit',
      14  => 'alert',
      15  => 'at',
      16  => 'local0',
      17  => 'local1',
      18  => 'local2',
      19  => 'local3',
      20  => 'local4',
      21  => 'local5',
      22  => 'local6',
      23  => 'local7'
    }

    PRIORITY_MAP = {
      0  => 'emerg',
      1  => 'alert',
      2  => 'crit',
      3  => 'err',
      4  => 'warn',
      5  => 'notice',
      6  => 'info',
      7  => 'debug'
    }

    desc 'The port to listen to.'
    config_param :port, :integer, default: 5140
    desc 'The bind address to listen to.'
    config_param :bind, :string, default: '0.0.0.0'
    desc 'The prefix of the tag. The tag itself is generated by the tag prefix, facility level, and priority.'
    config_param :tag, :string
    desc 'The transport protocol used to receive logs.(udp, tcp)'
    config_param :protocol_type, :enum, list: [:tcp, :udp], default: :udp

    desc 'If true, add source host to event record.'
    config_param :include_source_host, :bool, default: false, deprecated: 'use "source_hostname_key" or "source_address_key" instead.'
    desc 'Specify key of source host when include_source_host is true.'
    config_param :source_host_key, :string, default: 'source_host'.freeze

    desc 'The field name of hostname of sender.'
    config_param :source_hostname_key, :string, default: nil
    desc 'The field name of source address of sender.'
    config_param :source_address_key, :string, default: nil
    desc 'The field name of the priority.'
    config_param :priority_key, :string, default: nil
    desc 'The field name of the facility.'
    config_param :facility_key, :string, default: nil

    desc "The max bytes of message"
    config_param :message_length_limit, :size, default: 2048

    config_param :blocking_timeout, :time, default: 0.5

    config_section :parse do
      config_set_default :@type, DEFAULT_PARSER
      config_param :with_priority, :bool, default: true
    end

    def configure(conf)
      compat_parameters_convert(conf, :parser)

      super

      @use_default = false

      @parser = parser_create
      @parser_parse_priority = @parser.respond_to?(:with_priority) && @parser.with_priority

      if @include_source_host
        if @source_address_key
          raise Fluent::ConfigError, "specify either source_address_key or include_source_host"
        end
        @source_address_key = @source_host_key
      end
      @resolve_name = !!@source_hostname_key

      @_event_loop_run_timeout = @blocking_timeout
    end

    def multi_workers_ready?
      true
    end

    def start
      super

      log.info "listening syslog socket on #{@bind}:#{@port} with #{@protocol_type}"
      case @protocol_type
      when :udp then start_udp_server
      when :tcp then start_tcp_server
      else
        raise "BUG: invalid protocol_type value:#{@protocol_type}"
      end
    end

    def start_udp_server
      server_create_udp(:in_syslog_udp_server, @port, bind: @bind, max_bytes: @message_length_limit, resolve_name: @resolve_name) do |data, sock|
        message_handler(data.chomp, sock)
      end
    end

    def start_tcp_server
      # syslog family add "\n" to each message and this seems only way to split messages in tcp stream
      delimiter = "\n"
      delimiter_size = delimiter.size
      server_create_connection(:in_syslog_tcp_server, @port, bind: @bind, resolve_name: @resolve_name) do |conn|
        buffer = ""
        conn.data do |data|
          buffer << data
          pos = 0
          while idx = buffer.index(delimiter, pos)
            msg = buffer[pos...idx]
            pos = idx + delimiter_size
            message_handler(msg, conn)
          end
          buffer.slice!(0, pos) if pos > 0
        end
      end
    end

    private

    def message_handler(data, sock)
      pri = nil
      text = data
      unless @parser_parse_priority
        m = SYSLOG_REGEXP.match(data)
        unless m
          log.warn "invalid syslog message: #{data.dump}"
          return
        end
        pri = m[1].to_i
        text = m[2]
      end

      @parser.parse(text) do |time, record|
        unless time && record
          log.warn "failed to parse message", data: data
          return
        end

        pri ||= record.delete('pri')
        facility = FACILITY_MAP[pri >> 3]
        priority = PRIORITY_MAP[pri & 0b111]

        record[@priority_key] = priority if @priority_key
        record[@facility_key] = facility if @facility_key
        record[@source_address_key] = sock.remote_addr if @source_address_key
        record[@source_hostname_key] = sock.remote_host if @source_hostname_key

        tag = "#{@tag}.#{facility}.#{priority}"
        emit(tag, time, record)
      end
    rescue => e
      log.error "invalid input", data: data, error: e
      log.error_backtrace
    end

    def emit(tag, time, record)
      router.emit(tag, time, record)
    rescue => e
      log.error "syslog failed to emit", error: e, tag: tag, record: Yajl.dump(record)
    end
  end
end
