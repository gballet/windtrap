defmodule VMTest do
	use ExUnit.Case
  doctest Windtrap.VM

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
			%{code: %{0 => {:nop}, 1 => {:block_return}}}
		}
	}}

  test "execute simple module" do
    assert {:ok, module} = Windtrap.decode(@binaryen_dylib_wasm)
		module = module |> Windtrap.load_module(@env_mock)

    vm = Windtrap.VM.new([], 0, module)
		stopped_vm = Windtrap.VM.exec(vm, elem(module.codes, 0))
		assert 18 == stopped_vm.pc
	end

	test "check execution halts at breakpoint" do
		assert {:ok, module} = Windtrap.decode(@binaryen_dylib_wasm)
		module = Windtrap.load_module(module, @env_mock)
		vm = Windtrap.VM.new([], 0, module)
			|> Windtrap.VM.break(12)
			|> Windtrap.VM.exec(elem(module.codes, 0))
		assert 12 == vm.pc
	end
end
