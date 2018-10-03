defmodule WindtrapTest do
	use ExUnit.Case
	doctest Windtrap

	@binaryen_dylib_wasm <<0, 97, 115, 109, 1, 0, 0, 0, 0, 12, 6, 100, 121, 108, 105, 110, 107, 144, 128, 192, 2, 0, 1, 141, 128, 128, 128, 0, 3, 96, 1, 127, 1, 127, 96, 0, 1, 127, 96, 0, 0, 2, 205, 128, 128, 128, 0, 5, 3, 101, 110, 118, 10, 109, 101, 109, 111, 114, 121, 66, 97, 115, 101, 3, 127, 0, 3, 101, 110, 118, 5, 95, 112, 117, 116, 115, 0, 0, 3, 101, 110, 118, 6, 109, 101, 109, 111, 114, 121, 2, 0, 128, 2, 3, 101, 110, 118, 5, 116, 97, 98, 108, 101, 1, 112, 0, 0, 3, 101, 110, 118, 9, 116, 97, 98, 108, 101, 66, 97, 115, 101, 3, 127, 0, 3, 132, 128, 128, 128, 0, 3, 1, 2, 2, 6, 144, 128, 128, 128, 0, 3, 127, 1, 65, 0, 11, 127, 1, 65, 0, 11, 127, 0, 65, 0, 11, 7, 179, 128,
	128, 128, 0, 4, 18, 95, 95, 112, 111, 115, 116, 95, 105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 101, 0, 3, 5, 95, 109, 97, 105, 110, 0, 1, 11, 114, 117, 110, 80, 111, 115, 116, 83, 101, 116, 115, 0, 2, 4, 95, 115, 116, 114, 3, 4, 9, 129, 128, 128, 128, 0, 0, 10, 183, 128, 128, 128, 0, 3, 140, 128, 128, 128, 0, 0, 2, 127, 35, 0, 16, 0, 26, 65, 0, 11, 11, 131, 128, 128, 128, 0, 0, 1, 11, 152, 128, 128, 128, 0, 0, 2, 64, 35, 0, 65, 16, 106, 36, 2, 35, 2, 65, 128, 128, 192, 2, 106, 36, 3, 16, 2, 11, 11, 11, 147, 128, 128, 128, 0, 1, 0, 35, 0, 11, 13, 104, 101, 108, 108, 111, 44, 32, 119, 111, 114, 108, 100, 33>>

	@env_mock %{"env" => %Windtrap.Module{
		exports: %{
			"_puts" => %{type: :funcidx, idx: 0},
			"table" => %{type: :table, idx: 0 },
			"memoryBase" => %{type: :global, idx: 0},
			"tableBase" => %{type: :global, idx: 1},
			"memory" => %{type: :memory, idx: 0 }
		},
		codes: {
			%{0 => {:nop}}
		}
	}}

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

	test "global module function can be decoded" do
		{:ok, m} = Windtrap.decode(@binaryen_dylib_wasm)
		assert tuple_size(m.codes) == 3
		assert tuple_size(m.types) == 3
		assert tuple_size(m.imports) == 5
		assert Map.size(m.sections) == 9
		assert [] == (Map.keys(m.sections) -- [0, 1, 2, 3, 6, 7, 9, 10, 11])
	end

	# tester imports
	# tester locals dans code
	test "function disassembly with increasing addresses" do
		{:ok, m} = Windtrap.decode(@binaryen_dylib_wasm)
		assert Map.has_key?(elem(m.codes, 1).code, 0) == false
	end

	test "function disassembly always ends in 0xb" do
		{:ok, m} = Windtrap.decode(@binaryen_dylib_wasm)
		Enum.map(Tuple.to_list(m.codes), fn code ->
			lastaddr = Enum.max Map.keys code.code
			assert {:block_return} = Map.get(code.code, lastaddr)
		end)
	end

	test "module resolution" do
		Windtrap.decode(@binaryen_dylib_wasm)
		|> elem(1)
		|> Windtrap.load_module(@env_mock)
		|> Map.get(:imports)
		|> Tuple.to_list
		|> Enum.each(fn imprt ->
			assert %{resolved: true, exportidx: idx} = imprt
			assert is_number(idx)

			etype = @env_mock[imprt.mod].exports[imprt.import].type
			assert imprt.type == if etype == :funcidx, do: :typeidx, else: etype
		end)
	end
end
