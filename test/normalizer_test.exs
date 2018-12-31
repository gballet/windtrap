defmodule NormalizerTest do
  use ExUnit.Case
  doctest Windtrap.Normalizer
  import Windtrap.Normalizer

  test "should normalize an instruction with no immediates" do
    # unreachable
    assert {<<1>>, %{}} = normalize(<<1>>)
  end

  test "should normalize an instruction with one immediate" do
    # call
    assert {<<0x10, 5, 0, 0, 0>>, %{}} = normalize(<<0x10, 5>>)
  end

  test "should normalize an instruction with two immediates" do
    # i32.load 10, 20
    assert {<<0x28, 10, 0, 0, 0, 20, 0, 0, 0>>, %{}} = normalize(<<0x28, 10, 20>>)
  end

  test "should normalize an if/end" do
    assert {<<65, 1, 0, 0, 0, 4, 64, 0, 0, 0, 1, 11>>, %{5 => %{addr: 5, type: 4}}} = normalize(<<65, 1, 4, 0x40, 1, 11>>)
  end

  test "should normalize an if/else/end" do
    assert {<<65, 1, 0, 0, 0, 4, 64, 0, 0, 0, 1, 5, 1, 11>>, %{5 => %{type: 4, elseloc: 11, addr: 5}}} = normalize(<<65, 1, 4, 0x40, 1, 5, 1, 11>>)
  end

  test "should normalize a block/end" do
    assert {<<2, 64, 0, 0, 0, 11>>, %{0 => %{addr: 0, type: 2}}} = normalize(<<2, 0x40, 0x0b>>)
  end

  test "should normalize a return" do
    assert {<<0x0f>>, %{}} = normalize(<<0x0f>>)
  end

  test "should normalize an indirect call" do
    assert {<<0x11, 0, 2, 0, 0, 0>>, %{}} = normalize(<<0x11, 128, 4, 0>>)
  end
end
