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


class ExecFilterOutput < BufferedOutput
  Plugin.register_output('exec_filter', self)

  def initialize
    super
  end

  SUPPORTED_FORMAT = {
    'tsv' => :tsv,
    'json' => :json,
    'msgpack' => :msgpack,
  }

  config_param :command, :string

  config_param :remove_prefix, :string, :default => nil
  config_param :add_prefix, :string, :default => nil

  # TODO in_format
  config_param :in_keys do |val|
    val.split(',')
  end

  config_param :out_format, :default => :tsv do |val|
    c = SUPPORTED_FORMAT[val]
    raise ConfigError, "Unsupported out_format '#{val}'" unless c
    c
  end
  config_param :out_keys, :default => [] do |val|  # for tsv format
    val.split(',')
  end

  config_param :tag, :string, :default => nil
  config_param :tag_key, :string, :default => nil

  config_param :time_key, :string, :default => nil
  config_param :time_format, :string, :default => nil

  config_param :localtime, :bool, :default => true
  config_param :num_children, :integer, :default => 1

  config_set_default :flush_interval, 1

  def configure(conf)
    super

    if localtime = conf['localtime']
      @localtime = true
    elsif utc = conf['utc']
      @localtime = false
    end

    if !@tag && !@tag_key
      raise ConfigError, "'tag' or 'tag_key' option is required on exec_filter output"
    end

    if @time_key
      if @time_format
        f = @time_format
        tf = TimeFormatter.new(f, @localtime)
        @time_format_proc = tf.method(:format)
        @time_parse_proc = Proc.new {|str| Time.strptime(str, f).to_i }
      else
        @time_format_proc = Proc.new {|time| time.to_s }
        @time_parse_proc = Proc.new {|str| str.to_i }
      end
    end

    if @remove_prefix
      @removed_prefix_string = @remove_prefix + '.'
      @removed_length = @removed_prefix_string.length
    end
    if @add_prefix
      @added_prefix_string = @add_prefix + '.'
    end

    case @out_format
    when :tsv
      if @out_keys.empty?
        raise ConfigError, "out_keys option is required on exec_filter output"
      end
      @parser = TSVParser.new(@out_keys, method(:on_message))

    when :json
      @parser = JSONParser.new(method(:on_message))

    when :msgpack
      @parser = MessagePackParser.new(method(:on_message))
    end
  end

  def start
    super

    @children = []
    @rr = 0
    begin
      @num_children.times do
        c = ChildProcess.new(@parser)
        c.start(@command)
        @children << c
      end
    rescue
      shutdown
      raise
    end
  end

  def before_shutdown
    super
    sleep 0.5  # TODO wait time before killing child process
  end

  def shutdown
    super

    @children.reject! {|c|
      c.shutdown
      true
    }
  end

  def format_stream(tag, es)
    out = ''
    if @remove_prefix
      if (tag[0, @removed_length] == @removed_prefix_string and tag.length > @removed_length) or tag == @removed_prefix
        tag = tag[@removed_length..-1] || ''
      end
    end

    es.each {|time,record|
      last = @in_keys.length-1
      for i in 0..last
        key = @in_keys[i]
        if key == @time_key
          out << @time_format_proc.call(time)
        elsif key == @tag_key
          out << tag
        else
          out << record[key].to_s
        end
        out << "\t" if i != last
      end
      out << "\n"
    }

    out
  end

  def write(chunk)
    r = @rr = (@rr + 1) % @children.length
    @children[r].write chunk
  end

  class ChildProcess
    def initialize(parser)
      @pid = nil
      @thread = nil
      @parser = parser
    end

    def start(command)
      @io = IO.popen(command, "r+")
      @pid = @io.pid
      @io.sync = true
      @thread = Thread.new(&method(:run))
    end

    def shutdown
      begin
        Process.kill(:TERM, @pid)
      rescue Errno::ESRCH
        if $!.message == 'No such process'
          # child process killed by signal chained from fluentd process
        else
          raise
        end
      end
      if @thread.join(60)  # TODO wait time
        return
      end
      begin
        Process.kill(:KILL, @pid)
      rescue Errno::ESRCH
        if $!.message == 'No such process'
          # ignore if successfully killed by :TERM
        else
          raise
        end
      end
      @thread.join
    end

    def write(chunk)
      chunk.write_to(@io)
    end

    def run
      @parser.call(@io)
    rescue
      $log.error "exec_filter process exited", :error=>$!.to_s
      $log.warn_backtrace $!.backtrace
    ensure
      Process.waitpid(@pid)
    end
  end

  def on_message(record)
    if val = record.delete(@time_key)
      time = @time_parse_proc.call(val)
    else
      time = Engine.now
    end

    if val = record.delete(@tag_key)
      tag = if @add_prefix
              @added_prefix_string + val
            else
              val
            end
    else
      tag = @tag
    end

    Engine.emit(tag, time, record)

  rescue
    $log.error "exec_filter failed to emit", :error=>$!.to_s, :record=>Yajl.dump(record)
    $log.warn_backtrace $!.backtrace
  end

  class Parser
    def initialize(on_message)
      @on_message = on_message
    end
  end

  class TSVParser < Parser
    def initialize(out_keys, on_message)
      @out_keys = out_keys
      super(on_message)
    end

    def call(io)
      io.each_line(&method(:each_line))
    end

    def each_line(line)
      line.chomp!
      vals = line.split("\t")

      record = Hash[@out_keys.zip(vals)]

      @on_message.call(record)
    end
  end

  class JSONParser < Parser
    def call(io)
      y = Yajl::Parser.new
      y.on_parse_complete = @on_message
      y.parse(io)
    end
  end

  class MessagePackParser < Parser
    def call(io)
      @u = MessagePack::Unpacker.new(io)
      begin
        @u.each(&@on_message)
      rescue EOFError
      end
    end
  end
end


end

