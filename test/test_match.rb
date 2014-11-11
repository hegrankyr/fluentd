require 'helper'
require 'fluent/match'

class MatchTest < Test::Unit::TestCase
  include Fluent

  def test_simple
    assert_glob_match('a', 'a')
    assert_glob_match('a.b', 'a.b')
    assert_glob_not_match('a', 'b')
    assert_glob_not_match('a.b', 'aab')
  end

  def test_wildcard
    assert_glob_match('a*', 'a')
    assert_glob_match('a*', 'ab')
    assert_glob_match('a*', 'abc')

    assert_glob_match('*a', 'a')
    assert_glob_match('*a', 'ba')
    assert_glob_match('*a', 'cba')

    assert_glob_match('*a*', 'a')
    assert_glob_match('*a*', 'ba')
    assert_glob_match('*a*', 'ac')
    assert_glob_match('*a*', 'bac')

    assert_glob_not_match('a*', 'a.b')
    assert_glob_not_match('a*', 'ab.c')
    assert_glob_not_match('a*', 'ba')
    assert_glob_not_match('*a', 'ab')

    assert_glob_match('a.*', 'a.b')
    assert_glob_match('a.*', 'a.c')
    assert_glob_not_match('a.*', 'ab')

    assert_glob_match('a.*.c', 'a.b.c')
    assert_glob_match('a.*.c', 'a.c.c')
    assert_glob_not_match('a.*.c', 'a.c')
  end

  def test_recursive_wildcard
    assert_glob_match('a.**', 'a')
    assert_glob_not_match('a.**', 'ab')
    assert_glob_not_match('a.**', 'abc')
    assert_glob_match('a.**', 'a.b')
    assert_glob_not_match('a.**', 'ab.c')
    assert_glob_not_match('a.**', 'ab.d.e')

    assert_glob_match('a**', 'a')
    assert_glob_match('a**', 'ab')
    assert_glob_match('a**', 'abc')
    assert_glob_match('a**', 'a.b')
    assert_glob_match('a**', 'ab.c')
    assert_glob_match('a**', 'ab.d.e')

    assert_glob_match('**.a', 'a')
    assert_glob_not_match('**.a', 'ba')
    assert_glob_not_match('**.a', 'c.ba')
    assert_glob_match('**.a', 'b.a')
    assert_glob_match('**.a', 'cb.a')
    assert_glob_match('**.a', 'd.e.a')

    assert_glob_match('**a', 'a')
    assert_glob_match('**a', 'ba')
    assert_glob_match('**a', 'c.ba')
    assert_glob_match('**a', 'b.a')
    assert_glob_match('**a', 'cb.a')
    assert_glob_match('**a', 'd.e.a')
  end

  def test_or
    assert_glob_match('a.{b,c}', 'a.b')
    assert_glob_match('a.{b,c}', 'a.c')
    assert_glob_not_match('a.{b,c}', 'a.d')

    assert_glob_match('a.{b,c}.**', 'a.b')
    assert_glob_match('a.{b,c}.**', 'a.c')
    assert_glob_not_match('a.{b,c}.**', 'a.d')
    assert_glob_not_match('a.{b,c}.**', 'a.cd')

    assert_glob_match('a.{b.**,c}', 'a.b')
    assert_glob_match('a.{b.**,c}', 'a.b.c')
    assert_glob_match('a.{b.**,c}', 'a.c')
    assert_glob_not_match('a.{b.**,c}', 'a.c.d')
  end

  #def test_character_class
  #  assert_match('[a]', 'a')
  #  assert_match('[ab]', 'a')
  #  assert_match('[ab]', 'b')
  #  assert_not_match('[ab]', 'c')
  #
  #  assert_match('[a-b]', 'a')
  #  assert_match('[a-b]', 'a')
  #  assert_match('[a-b]', 'b')
  #  assert_not_match('[a-b]', 'c')
  #
  #  assert_match('[a-b0-9]', 'a')
  #  assert_match('[a-b0-9]', '0')
  #  assert_not_match('[a-b0-9]', 'c')
  #end

  def assert_glob_match(pat, str)
    m = GlobMatchPattern.new(pat)
    assert_true m.match(str)
  end

  def assert_glob_not_match(pat, str)
    m = GlobMatchPattern.new(pat)
    assert_false m.match(str)
  end
end
