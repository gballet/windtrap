defmodule VarintTest do
  use ExUnit.Case
  doctest Windtrap

  test "single-byte varint" do
		{val, <<extra :: big-size(32)>>} = Windtrap.Varint.varint(<<0x72, 0xde, 0xad, 0xbe, 0xef>>)
		assert val == 0x72
		assert extra == 0xdeadbeef
	end

	test "multi-byte varint" do
		{val, <<extra :: big-size(32)>>} = Windtrap.Varint.varint(<<0x83, 0x15, 0xde, 0xad, 0xbe, 0xef>>)
		assert val == 0xa83
		assert extra == 0xdeadbeef
  end

  test "complex varint when it should be simple" do
		{val, <<extra :: binary>>} = Windtrap.Varint.varint(<<0x8d, 0x80, 0x80, 0x80, 0x00>>)
		assert val == 13
		assert String.length(extra) == 0
	end
end
