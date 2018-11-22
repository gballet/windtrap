defmodule NormalizerTest do
  use ExUnit.Case
  doctest Windtrap.Normalizer
  import Windtrap.Normalizer

  test "should normalize an instruction with no immediates" do
    # unreachable
    assert <<1>> = normalize(<<1>>)
  end

  test "should normalize an instruction with one immediate" do
    # call
    assert <<0x10, 5, 0, 0, 0>> = normalize(<<0x10, 5>>)
  end

  test "should normalize an instruction with two immediates" do
    # i32.load 10, 20
    assert <<0x28, 10, 0, 0, 0, 20, 0, 0, 0>> = normalize(<<0x28, 10, 20>>)
  end

  test "should normalize an else" do
    assert <<5>> = normalize(<<5>>)
  end

  test "should normalize an end" do
    assert <<0x0b>> = normalize(<<0x0b>>)
  end

  test "should normalize a return" do
    assert <<0x0f>> = normalize(<<0x0f>>)
  end

  test "should normalize an indirect call" do
    assert <<0x11, 0, 2, 0, 0, 0>> = normalize(<<0x11, 128, 4, 0>>)
  end
end
