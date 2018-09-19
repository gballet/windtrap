defmodule WindtrapTest do
	use ExUnit.Case
	doctest Windtrap

	test "single-byte varint" do
		{val, <<extra :: big-size(32)>>} = Windtrap.varint_size(<<0x72, 0xde, 0xad, 0xbe, 0xef>>)
		assert val == 0x72
		assert extra == 0xdeadbeef
	end

	test "multi-byte varint" do
		{val, <<extra :: big-size(32)>>} = Windtrap.varint_size(<<0x83, 0x15, 0xde, 0xad, 0xbe, 0xef>>)
		assert val == 0xa83
		assert extra == 0xdeadbeef
	end

	test "complex when it should be simple" do
		{val, <<extra :: binary>>} = Windtrap.varint_size(<<0x8d, 0x80, 0x80, 0x80, 0x00>>)
		assert val == 13
		assert String.length(extra) == 0
	end

	test "unfurl invalid vector" do
		assert_raise FunctionClauseError, fn ->
			Windtrap.vec(<<>>)
		end
	end

	test "unfurl empty vector" do
		{sig, _} = Windtrap.vec(<<0>>)
		assert {} = sig
	end

	test "unfurl single-value vector" do
		{sig, _} = Windtrap.vec(<<01, 0x7f>>)
		assert {:i32} = sig
	end

	test "unfurl multiple-value vector" do
		{sig, _} = Windtrap.vec(<<03, 0x7f, 0x7f, 0x7f>>)
		assert {:i32, :i32, :i32} == sig
	end

	test "unfurl function vector" do
		{sig, _} = Windtrap.vec(<<3, 0x60, 1, 0x7f, 1, 0x7f, 0x60, 0, 1, 0x7f, 0x60, 0, 0>>)
		assert tuple_size(sig) == 3
		assert elem(sig, 0) == {{:i32}, {:i32}}
		assert elem(sig, 1) == {{}, {:i32}}
		assert elem(sig, 2) == {{}, {}}
	end
end
