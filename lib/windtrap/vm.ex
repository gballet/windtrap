defmodule Windtrap.VM do
	use Bitwise
	import Windtrap.Stepper

	@moduledoc """
	"""

	defstruct stack: [],
						pc: 0,
						memory: <<>>,
						breakpoints: %{},
						module: %Windtrap.Module{},
						resume: false,
						terminated: false,
						frames: [],
						globals: {},
						code: <<>>,
						jump_table: %{}

	defp mem_write vm, align, offset, value do
		<<before :: binary-size(offset), _::binary-size(align), rest :: binary>> = vm.memory
		Map.put vm, :memory, before <> <<value :: integer-little-size(align)>> <> rest
	end

	def new(args, startaddr, module) when is_list(args) and is_integer(startaddr) do
		%Windtrap.VM{
			stack: args,
			pc: startaddr,
			module: module,
			resume: false,
			globals: Enum.reduce(Map.keys(module.globals), %{}, fn (idx, acc) ->
				Map.put(acc, idx, module.globals[idx].value)
			end)
		}
	end

	@doc """
	Given a VM and a function index, this helper function returns the
	module and the associated data.
	"""
	def get_function(vm, idx) do
		case vm.module.functions[idx] do
			%{type: :local, addr: addr} -> {addr, false, vm.module}
			%{type: :host, func: f} -> {f, true, vm.module}
			%{type: :import, modname: modname, importname: imprt, tidx: _tidx} ->
				mod = vm.module.dependencies[modname]
				%{idx: funcidx, type: :funcidx} = mod.exports[imprt]

				# Recurse to get module's function, pc doesn't matter as
				# the vm object is temporary.
				get_function(Windtrap.VM.new(vm.stack, 0, mod), funcidx)
			%{type: t} -> raise "Unsupported call type: `#{t}`"
		end
	end

	def exec_binary(vm) do
		cond do
			# Breakpoint management
			vm.pc in Map.keys(vm.breakpoints) && vm.resume == false ->
				%{count: count, callback: callback} = vm.breakpoints[vm.pc]
				nvm = Map.put(vm, :breakpoints, Map.put(vm.breakpoints, vm.pc, %{count: count+1, callback: callback}))
				unless is_nil(callback), do: callback.(nvm), else: nvm
			# Stop condition, don't want to make it too complex for now
			vm.terminated == true ->
				vm
			# Execution
			true ->
				pc = vm.pc
				vm = vm |> Map.put(:code, vm.module.code) |> Map.put(:resume, false)
				<< _temp :: binary-size(pc), instr, _ :: binary>> = vm.code
				case next(vm, instr) do
					{:ok, vm, args} ->
						exec_instr_b(vm, instr, args) |>	exec_binary()
					{:error, e} -> IO.puts e
				end
		end
	end

	defp unsigned(x, size) do
		<<y :: integer-signed-little-size(size)>> = <<x :: integer-little-size(size)>>
		y
	end

	defp exec_instr_b(vm, 0, ""), do: raise "Reached unreachable at #{vm.pc-1}"
	defp exec_instr_b(vm, 1, ""), do: vm
	defp exec_instr_b(vm, 2, type), do:	Map.put(vm, :frames, [{:block,type,vm.pc}|vm.frames])
	defp exec_instr_b(vm, 3, type), do: Map.put(vm, :frames, [{:loop,type,vm.pc}|vm.frames])
	defp exec_instr_b(vm, 4, type), do: Map.put(vm, :frames, [{:if,type,vm.pc}|vm.frames])
	defp exec_instr_b(vm, 0xb, "") do
		case vm do
			%Windtrap.VM{frames: [{blocktype,return_vm,ref_pc}|rest]} ->
				case blocktype do
					:block ->
						Map.put(vm,:frames, rest)
					:call ->
						vm
						|> Map.put(:frames, rest)
						|> Map.put(:pc, ref_pc)
					:import_call ->
						return_vm
					:loop -> raise "Not supported yet"
					:if -> raise "Not supported yet"
					_ -> raise "Invalid type #{blocktype}"
				end
			%Windtrap.VM{frames: []} ->
				if length(vm.stack) > 1, do: raise "Invalid stack content: size = #{length(vm.stack)} != 0 or 1"
				retval = if length(vm.stack) == 1, do: hd(vm.stack), else: nil
				# End of the main function
				vm
				|> Map.put(:terminated, true)
				|> Map.put(:return_value, retval)
			_ -> raise "Invalid VM object"
		end
	end
	defp exec_instr_b(%Windtrap.VM{frames: frames} = vm, 0xc, idx) do
		[{_,_,pc}|rest] = Enum.slice(frames, idx..-1)

		vm
		|> Map.put(:pc, pc)
		|> Map.put(:frames, rest)
	end
	defp exec_instr_b(%Windtrap.VM{frames: frames, stack: stack} = vm, 0xd, idx) do
		[{_,_,pc}|restf] = Enum.slice(frames, idx..-1)
		[val|rests] = stack

		if val == 0 do
			Map.put(vm, :stack, rests)
		else
			vm
			|> Map.put(:pc, pc)
			|> Map.put(:stack, rests)
			|> Map.put(:frames, restf)
		end
	end
	defp exec_instr_b(%Windtrap.VM{stack: [{:call,_,pc}|rest]} = vm, 0xf, "") do
		vm
		|> Map.put(:pc, pc)
		|> Map.put(:stack, rest)
	end
	defp exec_instr_b(%Windtrap.VM{stack: [_|rest]} = vm, 0xf, "") do
		vm
		|> Map.put(:stack, rest)
		|> exec_instr_b(0xf, "")
	end
	defp exec_instr_b(vm, 0x10, idx) do
		{pc, host, mod} = Windtrap.VM.get_function(vm, idx)
		cond do
			host == true ->
				arity = :erlang.fun_info(pc)[:arity]
				if length(vm.stack) < arity, do: raise "Not enough parameters on the stack"
				ret = apply(pc, Enum.take(vm.stack, arity))
				stack = if ret != :ok do
					[ret | Enum.drop(vm.stack, arity)]
				else
					Enum.drop(vm.stack, arity)
				end

				Map.put(vm, :stack, stack)
			mod == vm.module ->
				vm
				|> Map.put(:frames, [{:call, mod, vm.pc}|vm.frames])
				|> Map.put(:pc, pc)
			mod ->
				call_vm = Windtrap.VM.new(vm.stack, pc, mod)
				|> Map.put(:frames, [{:import_call,vm,vm.pc}|vm.frames])
				|> exec_binary

				# Return the initial VM after the call
				vm
				|> Map.put(vm.stack, call_vm.stack)
		end
	end
	defp exec_instr_b(%Windtrap.VM{stack: [_|rest]} = vm, 0x1a, ""), do: Map.put(vm, :stack, rest)
	defp exec_instr_b(%Windtrap.VM{stack: [val1|[val2|[det|rest]]]} = vm, 0x1b, ""), do:	Map.put(vm, :stack, [(if det == 0, do: val1, else: val2)|rest])
	defp exec_instr_b(%Windtrap.VM{globals: globals} = vm, 0x23, idx), do:	Map.put(vm, :stack, [globals[idx] | vm.stack])
	defp exec_instr_b(%Windtrap.VM{globals: globals, stack: [val|rest]} = vm, 0x24, idx) do
		vm
		|> Map.put(:stack, rest)
		|> Map.put(:globals, Map.put(globals, idx, val))
	end
	defp exec_instr_b(vm, 0x41, val), do: Map.put(vm, :stack, [val|vm.stack])
	defp exec_instr_b(%Windtrap.VM{stack: [a|rest]} = vm, instr, "") when instr in [0x45, 0x50], do: Map.put(vm, :stack, [(if a==0, do: 1, else: 0)|rest])
	defp exec_instr_b(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x46, ""), do: Map.put(vm, :stack, [(if a==b, do: 1, else: 0)|rest])
	defp exec_instr_b(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x47, ""), do: Map.put(vm, :stack, [(if a==b, do: 0, else: 1)|rest])
	defp exec_instr_b(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x48, ""), do: Map.put(vm, :stack, [(if a<b, do: 0, else: 1)|rest])
	defp exec_instr_b(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x49, ""), do: Map.put(vm, :stack, [(if unsigned(a,32)<unsigned(b,32), do: 0, else: 1)|rest])
	defp exec_instr_b(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x4a, ""), do: Map.put(vm, :stack, [(if a>b, do: 0, else: 1)|rest])
	defp exec_instr_b(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x4b, ""), do: Map.put(vm, :stack, [(if unsigned(a,32)>unsigned(b,32), do: 0, else: 1)|rest])
	defp exec_instr_b(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x4c, ""), do: Map.put(vm, :stack, [(if a<=b, do: 0, else: 1)|rest])
	defp exec_instr_b(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x4d, ""), do: Map.put(vm, :stack, [(if unsigned(a,32)<=unsigned(b,32), do: 0, else: 1)|rest])
	defp exec_instr_b(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x4e, ""), do: Map.put(vm, :stack, [(if a>=b, do: 0, else: 1)|rest])
	defp exec_instr_b(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x4f, ""), do: Map.put(vm, :stack, [(if unsigned(a,32)>=unsigned(b,32), do: 0, else: 1)|rest])
	defp exec_instr_b(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x51, ""), do: Map.put(vm, :stack, [(if a==b, do: 1, else: 0)|rest])
	defp exec_instr_b(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x52, ""), do: Map.put(vm, :stack, [(if a==b, do: 0, else: 1)|rest])
	defp exec_instr_b(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x53, ""), do: Map.put(vm, :stack, [(if a<b, do: 0, else: 1)|rest])
	defp exec_instr_b(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x54, ""), do: Map.put(vm, :stack, [(if unsigned(a,64)<unsigned(b,64), do: 0, else: 1)|rest])
	defp exec_instr_b(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x55, ""), do: Map.put(vm, :stack, [(if a>b, do: 0, else: 1)|rest])
	defp exec_instr_b(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x56, ""), do: Map.put(vm, :stack, [(if unsigned(a,64)>unsigned(b,64), do: 0, else: 1)|rest])
	defp exec_instr_b(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x57, ""), do: Map.put(vm, :stack, [(if a<=b, do: 0, else: 1)|rest])
	defp exec_instr_b(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x58, ""), do: Map.put(vm, :stack, [(if unsigned(a,64)<=unsigned(b,64), do: 0, else: 1)|rest])
	defp exec_instr_b(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x59, ""), do: Map.put(vm, :stack, [(if a>=b, do: 0, else: 1)|rest])
	defp exec_instr_b(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x5a, ""), do: Map.put(vm, :stack, [(if unsigned(a,64)>=unsigned(b,64), do: 0, else: 1)|rest])
	defp exec_instr_b(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x6a, ""), do: Map.put(vm, :stack, [(a+b)|rest])

	defp exec_instr_b(_, instr, _), do: raise "Invalid instruction #{instr}"

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
		if !Map.has_key?(vm.breakpoints, vm.pc) || vm.halted do
			exec_instr(Map.put(vm, :halted, false), f, next_instr)
		else
			Map.put(vm, :halted, true)
		end
	end

	defp exec_instr(vm, f, {:nop}) do
		exec_next_instr Map.put(vm, :pc, vm.pc+1), f, f.code[vm.pc+1]
	end
	defp exec_instr(vm, f, {:block, _valtype}) do
		exec_next_instr Map.put(vm, :pc, vm.pc+2), f, f.code[vm.pc+2]
	end
	defp exec_instr(%Windtrap.VM{globals: globals} = vm, f, {:get_global, idx}) when idx < tuple_size(globals) do
		value = elem(globals, idx)

		vm
		|> Map.put(:pc, vm.pc+5)
		|> Map.put(:stack, [value | vm.stack])
		|> exec_next_instr(f, f.code[vm.pc+5])
	end
	defp exec_instr(%Windtrap.VM{globals: globals} = vm, f, {:set_global, idx}) when idx < tuple_size(globals) do
		[value | newlevel] = vm.stack
		vm
		|> Map.put(:pc, vm.pc+5)
		|> Map.put(:stack, newlevel)
		|> Map.put(:globals, Tuple.insert_at(Tuple.delete_at(globals, idx), idx, value))
		|> exec_next_instr(f, f.code[vm.pc+5])
	end
	defp exec_instr(vm, f, {:"i32.load", offset, align}) when align == 4 do
		<<_ :: binary-size(offset), value :: integer-size(32), _ :: binary>> = vm.memory
		vm
		|> Map.put(:stack, [value | vm.stack])
		|> Map.put(:pc, vm.pc+9)
		|> exec_next_instr(f, f.code[vm.pc+9])
	end
	defp exec_instr(vm, f, {:"i64.load", offset, align}) when align == 8 do
		<<_ :: binary-size(offset), value :: integer-size(64), _ :: binary>> = vm.memory
		vm
		|> Map.put(:stack, [value | vm.stack])
		|> Map.put(:pc, vm.pc+9)
		|> exec_next_instr(f, f.code[vm.pc+9])
	end
	defp exec_instr(vm, f, {:"f32.load", offset, align}) when align == 4 do
		<<_ :: binary-size(offset), value :: float-size(32), _ :: binary>> = vm.memory
		vm
		|> Map.put(:stack, [value | vm.stack])
		|> Map.put(:pc, vm.pc+9)
		|> exec_next_instr(f, f.code[vm.pc+9])
	end
	defp exec_instr(vm, f, {:"f64.load", offset, align}) when align == 8 do
		<<_ :: binary-size(offset), value :: float-size(64), _ :: binary>> = vm.memory
		vm
		|> Map.put(:stack, [value | vm.stack])
		|> Map.put(:pc, vm.pc+9)
		|> exec_next_instr(f, f.code[vm.pc+9])
	end
	defp exec_instr(vm, f, {:"i32.load8_s", offset, align}) when align == 4 do
		<<_ :: binary-size(offset), value :: integer-size(8), _ :: binary>> = vm.memory
		vm
		|> Map.put(:stack, [value | vm.stack])
		|> Map.put(:pc, vm.pc+9)
		|> exec_next_instr(f, f.code[vm.pc+9])
	end
	defp exec_instr(vm, f, {:"i32.load8_u", offset, align}) when align == 4 do
		<<_ :: binary-size(offset), value :: unsigned-integer-size(8), _ :: binary>> = vm.memory
		vm
		|> Map.put(:stack, [value | vm.stack])
		|> Map.put(:pc, vm.pc+9)
		|> exec_next_instr(f, f.code[vm.pc+9])
	end
	defp exec_instr(vm, f, {:"i32.load16_s", offset, align}) when align == 4 do
		<<_ :: binary-size(offset), value :: integer-size(16), _ :: binary>> = vm.memory
		vm
		|> Map.put(:stack, [value | vm.stack])
		|> Map.put(:pc, vm.pc+9)
		|> exec_next_instr(f, f.code[vm.pc+9])
	end
	defp exec_instr(vm, f, {:"i32.load16_u", offset, align}) when align == 4 do
		<<_ :: binary-size(offset), value :: unsigned-integer-size(16), _ :: binary>> = vm.memory
		vm
		|> Map.put(:stack, [value | vm.stack])
		|> Map.put(:pc, vm.pc+9)
		|> exec_next_instr(f, f.code[vm.pc+9])
	end
	defp exec_instr(vm, f, {:"i64.load8_s", offset, align}) when align == 8 do
		<<_ :: binary-size(offset), value :: integer-size(8), _ :: binary>> = vm.memory
		vm
		|> Map.put(:stack, [value | vm.stack])
		|> Map.put(:pc, vm.pc+9)
		|> exec_next_instr(f, f.code[vm.pc+9])
	end
	defp exec_instr(vm, f, {:"i64.load8_u", offset, align}) when align == 8 do
		<<_ :: binary-size(offset), value :: unsigned-integer-size(8), _ :: binary>> = vm.memory
		vm
		|> Map.put(:stack, [value | vm.stack])
		|> Map.put(:pc, vm.pc+9)
		|> exec_next_instr(f, f.code[vm.pc+9])
	end
	defp exec_instr(vm, f, {:"i64.load16_s", offset, align}) when align == 8 do
		<<_ :: binary-size(offset), value :: integer-size(16), _ :: binary>> = vm.memory
		vm
		|> Map.put(:stack, [value | vm.stack])
		|> Map.put(:pc, vm.pc+9)
		|> exec_next_instr(f, f.code[vm.pc+9])
	end
	defp exec_instr(vm, f, {:"i64.load16_u", offset, align}) when align == 8 do
		<<_ :: binary-size(offset), value :: unsigned-integer-size(16), _ :: binary>> = vm.memory
		vm
		|> Map.put(:stack, [value | vm.stack])
		|> Map.put(:pc, vm.pc+9)
		|> exec_next_instr(f, f.code[vm.pc+9])
	end
	defp exec_instr(vm, f, {:"i64.load32_s", offset, align}) when align == 8 do
		<<_ :: binary-size(offset), value :: integer-size(32), _ :: binary>> = vm.memory
		vm
		|> Map.put(:stack, [value | vm.stack])
		|> Map.put(:pc, vm.pc+9)
		|> exec_next_instr(f, f.code[vm.pc+9])
	end
	defp exec_instr(vm, f, {:"i64.load32_u", offset, align}) when align == 8 do
		<<_ :: binary-size(offset), value :: unsigned-integer-size(32), _ :: binary>> = vm.memory
		vm
		|> Map.put(:stack, [value | vm.stack])
		|> Map.put(:pc, vm.pc+9)
		|> exec_next_instr(f, f.code[vm.pc+9])
	end
	defp exec_instr(vm, f, {:"i32.store", align, offset}) when align == 4 do
		[value | rest ] = vm.stack
		vm
		|> mem_write(align, offset, value)
		|> Map.put(:pc, vm.pc+9)
		|> Map.put(:stack, rest)
		|> exec_next_instr(f, f[vm.pc+9])
	end
	defp exec_instr(vm, f, {:"i64.store", align, offset}) when align == 8 do
		[value | rest ] = vm.stack
		vm
		|> mem_write(align, offset, value)
		|> Map.put(:pc, vm.pc+9)
		|> Map.put(:stack, rest)
		|> exec_next_instr(f, f[vm.pc+9])
	end
	defp exec_instr(vm, f, {:"memory.size"}) do
		vm
		|> Map.put(:stack, [String.length(vm.memory) | vm.stack])
		|> Map.put(:pc, vm.pc+2)
		|> exec_next_instr(f, f.code[vm.pc+2])
	end
	defp exec_instr(vm, f, {:"memory.grow"}) do
		[s | rest] = vm.stack
		if s < 0, do: raise "Can not shrink memory"
		# check that we are page-aligned, otherwise round the
		# growth to the upper page.
		size = if rem(s, 4096) == 0, do: s, else: ((s &&& 4095) + 4096)
		vm
		|> Map.put(:stack, rest)
		|> Map.put(:pc, vm.pc+2)
		|> Map.put(:memory, vm.memory <> <<0 :: integer-unit(8)-size(size)>>)
		|> exec_next_instr(f, f.code[vm.pc+2])
	end
	defp exec_instr vm, f, {:"i32.const", c} do
		vm
		|> Map.put(:pc, vm.pc+5)
		|> Map.put(:stack, [c | vm.stack])
		|> exec_next_instr(f, f.code[vm.pc+5])
	end
	defp exec_instr vm, f, {:"i64.const", c} do
		vm
		|> Map.put(:pc, vm.pc+9)
		|> Map.put(:stack, [c | vm.stack])
		|> exec_next_instr(f, f.code[vm.pc+9])
	end
	defp exec_instr vm, f, {:"f32.const", c} do
		vm
		|> Map.put(:pc, vm.pc+5)
		|> Map.put(:stack, [c | vm.stack])
		|> exec_next_instr(f, f.code[vm.pc+5])
	end
	defp exec_instr vm, f, {:"f64.const", c} do
		vm
		|> Map.put(:pc, vm.pc+9)
		|> Map.put(:stack, [c | vm.stack])
		|> exec_next_instr(f, f.code[vm.pc+9])
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

	def restart vm do
		vm
		|> Map.put(:pc, 0)
		|> Map.put(:stack, [])
	end

	def resume vm do
		vm
		|> Map.put(:resume, true)
		|> exec_binary()
	end

	def break vm, addr do
		unless addr >= 0 && addr < byte_size(vm.module.code), do: raise("Invalid address")
		Map.put vm, :breakpoints, Map.put(vm.breakpoints, addr, %{count: 0, callback: nil})
	end

	def list vm do
		Enum.each(Enum.with_index(vm.breakpoints), fn {{addr, %{count: c, callback: cb}}, index} ->
			IO.puts "#{index+1} at #{addr} hit #{c} time(s)#{unless is_nil(cb), do: "has callback", else: ""}"
		end)
	end
end
