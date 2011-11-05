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
module Test


class InputTestDriver < TestDriver
  def initialize(klass, &block)
    super(klass, &block)
    @emits = []
    @expects = nil
  end

  def expect_emit(tag, time, record)
    (@expects ||= []) << [tag, time, record]
    self
  end

  def expected_emits
    @expects ||= []
  end

  attr_reader :emits

  def events
    all = []
    @emits.each {|tag,events|
      events.each {|time,record|
        all << [tag, time, record]
      }
    }
    all
  end

  def records
    all = []
    @emits.each {|tag,events|
      events.each {|time,record|
        all << record
      }
    }
    all
  end

  def run(&block)
    m = method(:emit_stream)
    super {
      Engine.define_singleton_method(:emit_stream) {|tag,es|
        m.call(tag, es)
      }

      block.call if block

      if @expects
        i = 0
        @emits.each {|tag,events|
          events.each {|time,record|
            assert_equal(@expects[i], [tag, time, record])
            i += 1
          }
        }
        assert_equal @expects.length, i
      end
    }
    self
  end

  private
  def emit_stream(tag, es)
    @emits << [tag, es.to_a]
  end
end


end
end
