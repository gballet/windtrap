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
						locals: %{},	# Locals of the current function
						params: {},	# Parameters of the current function
						code: <<>>,
						fidx: 0 # Index of the function being executed

	defp mem_write vm, align, offset, value do
		<<before :: binary-size(offset), _::binary-size(align), rest :: binary>> = vm.memory
		Map.put vm, :memory, before <> <<value :: integer-little-size(align)>> <> rest
	end

	def new(args, funcidx, module) when is_list(args) and is_integer(funcidx) do
		func = module.functions[funcidx]
		unless Map.has_key?(func, :type) and func.type == :host do
			%Windtrap.VM{
				stack: [],
				pc: func.addr,
				fidx: funcidx,
				module: module,
				resume: false,
				locals: func.locals,
				params: List.to_tuple(args),
				globals: Enum.reduce(Map.keys(module.globals), %{}, fn (idx, acc) ->
					Map.put(acc, idx, module.globals[idx].value)
				end)
			}
		else
			%Windtrap.VM{
				stack: [],
				pc: 0,
				fidx: funcidx,
				module: module,
				params: List.to_tuple(args),
				globals: Enum.reduce(Map.keys(module.globals), %{}, fn (idx, acc) ->
					Map.put(acc, idx, module.globals[idx].value)
				end)
			}
		end
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

	@doc """
	Execute WASM function `func`

	## Parameters

		* `vm` a `Windtrap.VM` object representing the current state of the
			virtual machine;
		* `func` a disassembled function that is to be executed.
	"""
	def exec(vm) do
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
						exec_instr(vm, instr, args) |>	exec()
					{:error, e} -> IO.puts e
				end
		end
	end

	defp unsigned(x, size) do
		<<y :: integer-signed-little-size(size)>> = <<x :: integer-little-size(size)>>
		y
	end

	defp exec_instr(vm, 0, ""), do: raise "Reached unreachable at #{vm.pc-1}"
	defp exec_instr(vm, 1, ""), do: vm
	defp exec_instr(vm, 2, type), do:	Map.put(vm, :frames, [{:block,type,vm.pc}|vm.frames])
	defp exec_instr(vm, 3, type), do: Map.put(vm, :frames, [{:loop,type,vm.pc}|vm.frames])
	defp exec_instr(vm, 4, _type) do
		[ok|rest] = vm.stack
		ifdesc = vm.module.functions[vm.fidx].jumps[vm.pc-7]
		pc = if ok != 0 do
			vm.pc
		else
			if Map.has_key?(ifdesc, :elseloc) do
				ifdesc.elseloc+3
			else
				ifdesc.endloc+2
			end
		end
		vm
		|> Map.put(:frames, [{:if,vm,ifdesc.endloc+2}|vm.frames])
		|> Map.put(:stack, rest)
		|> Map.put(:pc, pc)
	end
	defp exec_instr(vm, 5, "") do
		%{frames: [{:if,return_vm,ref_pc}|rest]} = vm
		return_vm
		|> Map.put(:frames, rest)
		|> Map.put(:pc, ref_pc)
		|> Map.put(:stack, vm.stack)
	end
	defp exec_instr(vm, 0xb, "") do
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

					:loop -> raise "not supported yet"
						vm
					:if ->
						vm
						|> Map.put(:pc, ref_pc)
						|> Map.put(:frames, rest)

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
	defp exec_instr(%Windtrap.VM{frames: frames} = vm, 0xc, idx) do
		[{_,_,pc}|rest] = Enum.slice(frames, idx..-1)

		vm
		|> Map.put(:pc, pc)
		|> Map.put(:frames, rest)
	end
	defp exec_instr(%Windtrap.VM{frames: frames, stack: stack} = vm, 0xd, idx) do
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
	defp exec_instr(%Windtrap.VM{stack: [{:call,_,pc}|rest]} = vm, 0xf, "") do
		vm
		|> Map.put(:pc, pc)
		|> Map.put(:stack, rest)
	end
	defp exec_instr(%Windtrap.VM{stack: [_|rest]} = vm, 0xf, "") do
		vm
		|> Map.put(:stack, rest)
		|> exec_instr(0xf, "")
	end
	defp exec_instr(vm, 0x10, idx) do
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
				|> exec

				# Return the initial VM after the call
				vm
				|> Map.put(vm.stack, call_vm.stack)
		end
	end
	defp exec_instr(%Windtrap.VM{stack: [_|rest]} = vm, 0x1a, ""), do: Map.put(vm, :stack, rest)
	defp exec_instr(%Windtrap.VM{stack: [val1|[val2|[det|rest]]]} = vm, 0x1b, ""), do:	Map.put(vm, :stack, [(if det == 0, do: val1, else: val2)|rest])
	defp exec_instr(%Windtrap.VM{fidx: fidx, module: mod} = vm, 0x20, idx) do
		f = mod.functions[fidx]
		if idx > f.nparams do
			Map.put(vm, :stack, [f.locals[idx-f.nparams] | vm.stack])
		else
			Map.put(vm, :stack, [elem(vm.params, idx) | vm.stack])
		end
	end
	defp exec_instr(%Windtrap.VM{fidx: fidx, module: mod} = vm, 0x21, idx) do
		f = mod.functions[fidx]
		[val|rest] = vm.stack
		f2 = if idx >= f.nparams do
			Map.put(f, :locals, Map.put(f.locals, idx-f.nparams, val))
		else
			Map.put(f, :params, vm.params |> Tuple.delete_at(idx) |> Tuple.insert_at(idx, val))
		end

		funcs = Map.put(mod.functions, fidx, f2)

		vm
			|> Map.put(:functions, funcs)
			|> Map.put(:stack, rest)
	end
	defp exec_instr(%Windtrap.VM{globals: globals} = vm, 0x23, idx), do: Map.put(vm, :stack, [globals[idx] | vm.stack])
	defp exec_instr(%Windtrap.VM{globals: globals, stack: [val|rest]} = vm, 0x24, idx) do
		vm
		|> Map.put(:stack, rest)
		|> Map.put(:globals, Map.put(globals, idx, val))
	end
	defp exec_instr(vm, 0x41, val), do: Map.put(vm, :stack, [val|vm.stack])
	defp exec_instr(%Windtrap.VM{stack: [a|rest]} = vm, instr, "") when instr in [0x45, 0x50], do: Map.put(vm, :stack, [(if a==0, do: 1, else: 0)|rest])
	defp exec_instr(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x46, ""), do: Map.put(vm, :stack, [(if a==b, do: 1, else: 0)|rest])
	defp exec_instr(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x47, ""), do: Map.put(vm, :stack, [(if a==b, do: 0, else: 1)|rest])
	defp exec_instr(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x48, ""), do: Map.put(vm, :stack, [(if a<b, do: 0, else: 1)|rest])
	defp exec_instr(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x49, ""), do: Map.put(vm, :stack, [(if unsigned(a,32)<unsigned(b,32), do: 0, else: 1)|rest])
	defp exec_instr(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x4a, ""), do: Map.put(vm, :stack, [(if a>b, do: 0, else: 1)|rest])
	defp exec_instr(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x4b, ""), do: Map.put(vm, :stack, [(if unsigned(a,32)>unsigned(b,32), do: 0, else: 1)|rest])
	defp exec_instr(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x4c, ""), do: Map.put(vm, :stack, [(if a<=b, do: 0, else: 1)|rest])
	defp exec_instr(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x4d, ""), do: Map.put(vm, :stack, [(if unsigned(a,32)<=unsigned(b,32), do: 0, else: 1)|rest])
	defp exec_instr(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x4e, ""), do: Map.put(vm, :stack, [(if a>=b, do: 0, else: 1)|rest])
	defp exec_instr(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x4f, ""), do: Map.put(vm, :stack, [(if unsigned(a,32)>=unsigned(b,32), do: 0, else: 1)|rest])
	defp exec_instr(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x51, ""), do: Map.put(vm, :stack, [(if a==b, do: 1, else: 0)|rest])
	defp exec_instr(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x52, ""), do: Map.put(vm, :stack, [(if a==b, do: 0, else: 1)|rest])
	defp exec_instr(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x53, ""), do: Map.put(vm, :stack, [(if a<b, do: 0, else: 1)|rest])
	defp exec_instr(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x54, ""), do: Map.put(vm, :stack, [(if unsigned(a,64)<unsigned(b,64), do: 0, else: 1)|rest])
	defp exec_instr(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x55, ""), do: Map.put(vm, :stack, [(if a>b, do: 0, else: 1)|rest])
	defp exec_instr(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x56, ""), do: Map.put(vm, :stack, [(if unsigned(a,64)>unsigned(b,64), do: 0, else: 1)|rest])
	defp exec_instr(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x57, ""), do: Map.put(vm, :stack, [(if a<=b, do: 0, else: 1)|rest])
	defp exec_instr(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x58, ""), do: Map.put(vm, :stack, [(if unsigned(a,64)<=unsigned(b,64), do: 0, else: 1)|rest])
	defp exec_instr(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x59, ""), do: Map.put(vm, :stack, [(if a>=b, do: 0, else: 1)|rest])
	defp exec_instr(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x5a, ""), do: Map.put(vm, :stack, [(if unsigned(a,64)>=unsigned(b,64), do: 0, else: 1)|rest])
	defp exec_instr(%Windtrap.VM{stack: [a|[b|rest]]} = vm, 0x6a, ""), do: Map.put(vm, :stack, [(a+b)|rest])

	defp exec_instr(_, instr, _), do: raise "Invalid instruction #{instr}"

	def restart vm do
		vm
		|> Map.put(:pc, 0)
		|> Map.put(:stack, [])
	end

	def resume vm do
		vm
		|> Map.put(:resume, true)
		|> exec()
	end

	def break vm, addr do
		unless addr >= 0 && addr < byte_size(vm.module.code), do: raise("Invalid address")
		Map.put vm, :breakpoints, Map.put(vm.breakpoints, addr, %{count: 0, callback: nil})
	end

	def list vm do
		IO.puts "Breakpoint list:"
		Enum.each(Enum.with_index(vm.breakpoints), fn {{addr, %{count: c, callback: cb}}, index} ->
			IO.puts "#{index+1} at #{addr} hit #{c} time(s)#{unless is_nil(cb), do: "has callback", else: ""}"
		end)
	end
end
