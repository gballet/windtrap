defmodule WindtrapTest do
	use ExUnit.Case
	doctest Windtrap

	# This test module has been taken from the binaryen test suite and
	# disassembles to the following WAST code:
	#
	# ```wast
	# (module
	#  (type $0 (func (param i32) (result i32)))
	#  (type $1 (func (result i32)))
	#  (type $2 (func))
	#  (import "env" "memoryBase" (global $gimport$0 i32))
	#  (import "env" "memory" (memory $0 256))
	#  (import "env" "table" (table 0 anyfunc))
	#  (import "env" "tableBase" (global $gimport$4 i32))
	#  (import "env" "_puts" (func $fimport$1 (param i32) (result i32)))
	#  (global $global$0 (mut i32) (i32.const 0))
	#  (global $global$1 (mut i32) (i32.const 0))
	#  (global $global$2 i32 (i32.const 0))
	#  (data (get_global $gimport$0) "hello, world!")
	#  (export "__post_instantiate" (func $2))
	#  (export "_main" (func $0))
	#  (export "runPostSets" (func $1))
	#  (export "_str" (global $global$2))
	#  (func $0 (; 1 ;) (type $1) (result i32)
	# 	(block $label$1 (result i32)
	#  	 (drop
	# 		(call $fimport$1
	# 		 (get_global $gimport$0)
	# 	  )
	# 	 )
	# 	 (i32.const 0)
	# 	)
	#  )
	#  (func $1 (; 2 ;) (type $2)
	# 	(nop)
	#  )
	#  (func $2 (; 3 ;) (type $2)
	# 	(block $label$1
	# 	 (set_global $global$0
	# 		(i32.add
	# 		 (get_global $gimport$0)
	# 		 (i32.const 16)
	# 		)
	# 	 )
	# 	 (set_global $global$1
	# 		(i32.add
	# 		 (get_global $global$0)
	# 		 (i32.const 5242880)
	# 		)
	# 	 )
	# 	 (call $1)
	# 	)
	#  )
	#  ;; custom section "dylink", size 5
	# )
	# ```
	#
	# It is therefore used to test the decoding of all
	# sections that are present in that file. Missing
	# sections are `element`, `start`, `table` and
	# `memory`.
	@binaryen_dylib_wasm <<0, 97, 115, 109, 1, 0, 0, 0, 0, 12, 6, 100, 121, 108, 105, 110, 107, 144, 128, 192, 2, 0, 1, 141, 128, 128, 128, 0, 3, 96, 1, 127, 1, 127, 96, 0, 1, 127, 96, 0, 0, 2, 205, 128, 128, 128, 0, 5, 3, 101, 110, 118, 10, 109, 101, 109, 111, 114, 121, 66, 97, 115, 101, 3, 127, 0, 3, 101, 110, 118, 5, 95, 112, 117, 116, 115, 0, 0, 3, 101, 110, 118, 6, 109, 101, 109, 111, 114, 121, 2, 0, 128, 2, 3, 101, 110, 118, 5, 116, 97, 98, 108, 101, 1, 112, 0, 0, 3, 101, 110, 118, 9, 116, 97, 98, 108, 101, 66, 97, 115, 101, 3, 127, 0, 3, 132, 128, 128, 128, 0, 3, 1, 2, 2, 6, 144, 128, 128, 128, 0, 3, 127, 1, 65, 0, 11, 127, 1, 65, 0, 11, 127, 0, 65, 0, 11, 7, 179, 128,
	128, 128, 0, 4, 18, 95, 95, 112, 111, 115, 116, 95, 105, 110, 115, 116, 97, 110, 116, 105, 97, 116, 101, 0, 3, 5, 95, 109, 97, 105, 110, 0, 1, 11, 114, 117, 110, 80, 111, 115, 116, 83, 101, 116, 115, 0, 2, 4, 95, 115, 116, 114, 3, 4, 9, 129, 128, 128, 128, 0, 0, 10, 183, 128, 128, 128, 0, 3, 140, 128, 128, 128, 0, 0, 2, 127, 35, 0, 16, 0, 26, 65, 0, 11, 11, 131, 128, 128, 128, 0, 0, 1, 11, 152, 128, 128, 128, 0, 0, 2, 64, 35, 0, 65, 16, 106, 36, 2, 35, 2, 65, 128, 128, 192, 2, 106, 36, 3, 16, 2, 11, 11, 11, 147, 128, 128, 128, 0, 1, 0, 35, 0, 11, 13, 104, 101, 108, 108, 111, 44, 32, 119, 111, 114, 108, 100, 33>>

	# Disassembles to:
	#
	# ```wast
	# (module
  #  (memory 16)
	#  (data (i32.const 512) "\be\ef")
	#  (export "memory" (memory 0))
	#  (export "main" (func $main))
	#  (start $main)
	#  (func $main
	#   (nop)
	#  )
  # )
	# ```
	@wasm_with_memory <<0, 97, 115, 109, 1, 0, 0, 0, 1, 4, 1, 96, 0, 0, 3, 2, 1, 0, 5, 3, 1, 0, 16, 7, 17, 2, 6, 109, 101, 109, 111, 114, 121, 2, 0, 4, 109, 97, 105, 110, 0, 0, 8, 1, 0, 10, 5, 1, 3, 0, 1, 11, 11, 9, 1, 0, 65, 128, 4, 11, 2, 190, 239>>

	@env_mock %{"env" => %Windtrap.Module{
		exports: %{
			"_puts" => %{type: :funcidx, idx: 0},
			"table" => %{type: :table, idx: 0 },
			"memoryBase" => %{type: :global, idx: 0},
			"tableBase" => %{type: :global, idx: 1},
			"memory" => %{type: :memory, idx: 0 }
		},
		codes: {
			%{code: %{0 => {:nop}}}
		}
	}}

	test "unfurl invalid vector" do
		assert_raise FunctionClauseError, fn ->
			Windtrap.vec(:types, <<>>)
		end
	end

	test "unfurl empty vector" do
		{sig, _} = Windtrap.vec(:types, <<0>>)
		assert {} = sig
	end

	test "unfurl single-value vector" do
		{sig, _} = Windtrap.vec(:types, <<01, 0x7f>>)
		assert {:i32} = sig
	end

	test "unfurl multiple-value vector" do
		{sig, _} = Windtrap.vec(:types, <<03, 0x7f, 0x7f, 0x7f>>)
		assert {:i32, :i32, :i32} == sig
	end

	test "unfurl function vector" do
		{sig, _} = Windtrap.vec(:types, <<3, 0x60, 1, 0x7f, 1, 0x7f, 0x60, 0, 1, 0x7f, 0x60, 0, 0>>)
		assert tuple_size(sig) == 3
		assert elem(sig, 0) == {{:i32}, {:i32}}
		assert elem(sig, 1) == {{}, {:i32}}
		assert elem(sig, 2) == {{}, {}}
	end

	test "module sections can be decoded" do
		{:ok, m} = Windtrap.decode(@binaryen_dylib_wasm)
		assert tuple_size(m.codes) == 3
		assert tuple_size(m.types) == 3
		assert tuple_size(m.imports) == 5
		assert tuple_size(m.globals) == 3
		assert tuple_size(m.exports) == 4
		assert tuple_size(m.data) == 1
		assert Map.size(m.sections) == 9
		assert [] == (Map.keys(m.sections) -- [0, 1, 2, 3, 6, 7, 9, 10, 11])
	end

	test "import section can be decoded" do
		{:ok, m} = Windtrap.decode(@binaryen_dylib_wasm)
		Enum.each Tuple.to_list(m.imports), fn imp ->
			assert "env" == imp.mod
			case imp.import do
				"memoryBase" ->
					assert true = imp.const
					assert :global == imp.type
					assert 127 == imp.valtype
				"_puts" ->
					assert 0 == imp.index
					assert :typeidx == imp.type
				"memory" ->
					assert 256 == imp.min
					assert !Map.has_key?(imp, :max)
					assert :memory == imp.type
				"table" ->
					assert 0 == imp.min
					assert !Map.has_key?(imp, :max)
					assert :table == imp.type
				"tableBase" ->
					assert true = imp.const
					assert :global == imp.type
					assert 127 == imp.valtype
				_ -> raise "Unexpected symbol #{imp.import} in import section"
			end
		end
	end

	test "function section can be decoded" do
		{:ok, m} = Windtrap.decode(@binaryen_dylib_wasm)
		assert 3 == tuple_size(m.functions)
		assert {1, 2, 2} == m.functions
		Enum.each Tuple.to_list(m.functions), fn typeidx ->
			assert typeidx >= 0
			assert typeidx < tuple_size(m.types)
		end
	end

	test "export section can be decoded" do
		{:ok, m} = Windtrap.decode(@binaryen_dylib_wasm)
		Enum.each Tuple.to_list(m.exports), fn exp ->
			case exp.export do
				"__post_instantiate" ->
					assert 3 == exp.index
					assert :funcidx == exp.type
				"_main" ->
					assert 1 == exp.index
					assert :funcidx == exp.type
				"runPostSets" ->
					assert 2 == exp.index
					assert :funcidx == exp.type
				"_str" ->
					assert 4 == exp.index
					assert :globalidx == exp.type
				_ -> raise "Unexpected symbol #{exp.export} in export section"
			end
		end
	end

	test "global section can be decoded" do
		{:ok, m} = Windtrap.decode(@binaryen_dylib_wasm)
		glob0 = elem(m.globals, 0)
		assert :var == glob0.mut
		assert 0 == glob0.value

		glob2 = elem(m.globals, 2)
		assert :const == glob2.mut
		assert 0 == glob2.value
	end

	test "memory section can be decoded" do
		{:ok, m} = Windtrap.decode(@wasm_with_memory)
		assert {%{min: 16}} = m.memory
	end

	test "start section can be decoded" do
		{:ok, m} = Windtrap.decode(@wasm_with_memory)
		assert 0 == m.start
	end

	test "empty element section can be decoded" do
		# The binaryen example actually has an element
		# section that has 0 elements.
		{:ok, m} = Windtrap.decode(@binaryen_dylib_wasm)
		assert {} = m.elements
	end

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
