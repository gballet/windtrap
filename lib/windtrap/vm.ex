defmodule Windtrap.VM do
	@moduledoc """
	"""

	defstruct stack: [],
						pc: 0,
						memory: <<>>,
						breakpoints: %{},
						module: %Windtrap.Module{},
						resume: false,
						frames: []

	defp mem_write vm, align, offset, value do
		<<before :: binary-size(offset), _::binary-size(align), rest :: binary>> = vm.memory
		Map.put vm, :memory, before <> <<value :: integer-little-size(align)>> <> rest
	end

	@doc """
	Execute WASM function `func`

	## Parameters

		* `vm` a `Windtrap.VM` object representing the current state of the
			virtual machine;
		* `func` a disassembled function that is to be executed.
	"""
	def exec(vm, func) do
			exec_next_instr(vm, func, func.code[vm.pc])
	end

	# This is an intermediate step that checks for breakpoints
	# Note: there is an issue in the interface because I have to
	# know which function the VM has been halted in, in order to
	# resume.
	defp exec_next_instr(vm, f, next_instr) do
		# If pc is in the breakpoint list, the function will return, and in iEx
		# this will prompt the user.
		if !Map.has_key?(vm.breakpoints, vm.pc) || vm.resume do
			exec_instr(Map.put(vm, :resume, false), f, next_instr)
		else
			Map.put(vm, :resume, true)
	end
	end

	defp exec_instr(vm, f, {:nop}) do
		exec_next_instr Map.put(vm, :pc, vm.pc+1), f, f.code[vm.pc+1]
	end
	defp exec_instr(vm, f, {:block, _valtype}) do
		exec_next_instr Map.put(vm, :pc, vm.pc+2), f, f.code[vm.pc+2]
	end
	defp exec_instr(vm, f, {:get_global, _idx}) do
		value = 0

		vm
		|> Map.put(:pc, vm.pc+5)
		|> exec_next_instr(f, f.code[vm.pc+5])
	end
	defp exec_instr vm, f, {:"i32.const", c} do
		vm
		|> Map.put(:pc, vm.pc+5)
		|> Map.put(:stack, [c | vm.stack])
		|> exec_next_instr(f, f.code[vm.pc+5])
	end
	defp exec_instr(vm, f, {:"i32.store", align, offset}) do
		[value | rest ] = vm.stack
		vm
		|> mem_write(align, offset, value)
		|> Map.put(:pc, vm.pc+9)
		|> Map.put(:stack, rest)
		|> exec_next_instr(f, f[vm.pc+9])
	end
	defp exec_instr(vm, f, {:call, fidx}) do
		# Get the type of the function to be called
		ftypeidx = elem(vm.module.functions, fidx)
		{inputs, _outputs} = elem(vm.module.types, ftypeidx)

		# Check the number of arguments on the stack
		if length(vm.stack) < tuple_size(inputs), do: raise("Insufficient number of arguments on the stack")

		# Check if this is the same module or not
		fdesc = elem(vm.module.function_index, fidx)
		unless Map.has_key?(fdesc, :exportidx) do
			%{code: f} = elem(vm.module.codes, fdesc.fidx)
			call_pc = Enum.min Map.keys f

			vm
			|> Map.put(:frames, [{vm.pc+5, vm.module, f} | vm.frames])
			|> Map.put(:pc, call_pc)
			|> exec(f)
		else
			# Get the destination module and index of the function in exports
			new_module = fdesc.module
			export = new_module.exports[fdesc.name]
			if export.type != :funcidx, do: raise("Tried to import a non-function as a function")
			code = elem(new_module.codes, export.idx)
			call_pc = if Map.has_key?(code, :code), do: (Enum.min Map.keys code.code), else: 0

			mod = vm.module

			vm
			|> Map.put(:module, new_module)
			|> Map.put(:frames, [{vm.pc+5, mod, f} | vm.frames])
			|> Map.put(:pc, call_pc)
			|> exec(code)
		end
	end
	defp exec_instr(vm, f, {:drop}) do
		[_|s] = vm.stack
		vm
		|> Map.put(:pc, vm.pc+1)
		|> Map.put(:stack, s)
		|> exec_next_instr(f, f.code[vm.pc+1])
	end
	defp exec_instr(vm, _, {:block_return}) do
		if vm.frames == [] do
			vm
		else
			[{return_pc, return_mod, return_f} | nested_frames] = vm.frames
			vm
			|> Map.put(:pc, return_pc)
			|> Map.put(:module, return_mod)
			|> Map.put(:frames, nested_frames)
			|> exec_next_instr(return_f, return_f.code[return_pc])
		end
	end
	def break vm, addr do
		found = Enum.reduce Tuple.to_list(vm.module.codes), false, fn (code, found) ->
			found || Map.has_key?(code.code, addr)
		end
		unless found, do: raise("Invalid address")
		Map.put vm, :breakpoints, Map.put(vm.breakpoints, addr, 0)
	end
end
