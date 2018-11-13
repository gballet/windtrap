defmodule Windtrap do
	@moduledoc """
	Documentation for Windtrap.
	"""

	import Windtrap.Varint

	@wasm_header (<<0>> <> "asm" <> << 1 ::little-size(32)>>)

	@section_types_id 1
	@section_imports_id 2
	@section_function_id 3
	@section_table_id 4
	@section_memory_id 5
	@section_globals_id 6
	@section_exports_id 7
	@section_start_id 8
	@section_element_id 9
	@section_code_id 10
	@section_data_id 11

	@resulttype 0x40
	@functype 0x60
	@f64type 0x7c
	@f32type 0x7d
	@i64type 0x7e
	@i32type 0x7f

	@doc """
	Decode a wasm binary.

	## Examples

	  iex> {:ok, %Windtrap.Module{}} = Windtrap.decode(<<0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00, 0x01, 0x09, 0x02, 0x60, 0x02, 0x7F, 0x7F, 0x00, 0x60, 0x00, 0x00, 0x02, 0x13, 0x01, 0x08, 0x65, 0x74, 0x68, 0x65, 0x72, 0x65, 0x75, 0x6D, 0x06, 0x72, 0x65, 0x76, 0x65, 0x72, 0x74, 0x00, 0x00, 0x03, 0x02, 0x01, 0x01, 0x05, 0x03, 0x01, 0x00, 0x01, 0x07, 0x11, 0x02, 0x06, 0x6D, 0x65, 0x6D, 0x6F, 0x72, 0x79, 0x02, 0x00, 0x04, 0x6D, 0x61, 0x69, 0x6E, 0x00, 0x01, 0x0A, 0x13, 0x01, 0x11, 0x00, 0x41, 0x00, 0x41, 0xCD, 0xD7, 0x02, 0x36, 0x02, 0x00, 0x41, 0x00, 0x41, 0x7F, 0x10, 0x00, 0x0B>>)
	  {:ok, %Windtrap.Module{exports: {%{export: "memory", index: 0, type: :memidx}, %{export: "main", index: 1, type: :funcidx}}, functions: {1}, imports: {%{import: "revert", index: 0, mod: "ethereum", type: :typeidx}}, sections: %{1 => <<2, 96, 2, 127, 127, 0, 96, 0, 0>>, 2 => <<1, 8, 101, 116, 104, 101, 114, 101, 117, 109, 6, 114, 101, 118, 101, 114, 116, 0, 0>>, 3 => <<1, 1>>, 5 => <<1, 0, 1>>, 7 => <<2, 6, 109, 101, 109, 111, 114, 121, 2, 0, 4, 109, 97, 105, 110, 0, 1>>, 10 => <<1, 17, 0, 65, 0, 65, 205, 215, 2, 54, 2, 0, 65, 0, 65, 127, 16, 0, 11>>}, types: {{{:i32, :i32}, {}}, {{}, {}}}, codes: {%{code: %{0 => {:"i32.const", 0}, 5 => {:"i32.const", 43981}, 10 => {:"i32.store", 2, 0}, 19 => {:"i32.const", 0}, 24 => {:"i32.const", 127}, 29 => {:call, 0}, 34 => {:block_return}}, locals: "", num_locals: 0}}, memory: {%{min: 1}}}}
	"""
	def decode(data) do
		try do
			d = data
			|> check_header
			|> decode_custom
			|> decode_types
			|> decode_imports
			|> decode_functions
			|> decode_table
			|> decode_memory
			|> decode_global
			|> decode_export
			|> decode_start
			|> decode_element
			|> decode_code
			|> decode_data

			{:ok, d}
		rescue
			e -> {:error, e}
		end

	end

	def decode_file filename do
		with {:ok, data} <- File.read(filename) do
			decode(data)
		else
			x -> x
		end
	end

	def dump module do
		types = Enum.reduce Tuple.to_list(module.types), "", fn {ins, outs}, acc ->
			acc <> "#{inspect ins} -> #{inspect outs}\n"
		end

		mmodsize = Tuple.to_list(module.imports) |> Enum.map(fn import -> String.length(import.mod) end) |> Enum.max
		mnamesize = Tuple.to_list(module.imports) |> Enum.map(fn import -> String.length(import.import) end) |> Enum.max

		imports = Enum.reduce Tuple.to_list(module.imports), "", fn import, acc ->
			modspaces = String.duplicate(" ", 1+mmodsize-String.length(import.mod))
			namespaces = String.duplicate(" ", 1+mnamesize-String.length(import.import))
			acc <> "#{import.mod}#{modspaces}:#{import.import}#{namespaces}#{import.type}\n"
		end

		ftypes = Enum.reduce Enum.with_index(Tuple.to_list(module.functions)), "", fn {fidx, tidx}, acc ->
			acc <> "$f#{tidx}: #{inspect(elem(module.types, fidx))}\n"
		end

		IO.puts """
		The module contains #{Enum.count(module.sections)} sections

		Types:
		#{types}

		Imports:
		#{imports}

		Function types:
		#{ftypes}
		"""
	end

	@doc """
	Load a file and resolve its imported modules.

	## Parameters

		* `filename` is the name of the file to be loaded
		* `imports` is a map that contains pre-loaded imports and whose format
			is `"module_name" => %Windtrap.Module{}`. If a module name is not
			present in `imports`, then the console will try to load "module_name.wasm"
			from the local directory.
	"""
	def load_file(filename, imports \\ %{}) do
		with {:ok, m} <- decode_file(filename),
				mod <- load_module(m, imports) do
					{:ok, mod}
			else
				x -> x
			end
	end

	@doc """
	Load a module's dependencies. A series of pre-resolved modules
	can be passed as an optional argument. If they can not be found
	there, then the function will try to load them from disk.

	## Parameters

		* `module` is the module whose dependencies will be loaded
		* `imports` is an optional hash whose keys are module names
			 and values are the actual, pre-loaded modules.

	## Returns

	An new version of the module, with the following updated
	fields:

		* `:function_index` will point to a list of all functions
			known to the module.
		* `:imports` will have its function entries updated to
			contain a `:resolved` field set to `true`, as well as
			the `:module` name and the index of the export in that
			module.
	"""
	def load_module(module, imports \\ %{}) do
		resolved = Enum.map Tuple.to_list(module.imports), fn imprt ->
			%{type: itype} = imprt
			# export and import entries have a slight discrepancy, make
			# sure all equality tests match.
			etype = if itype == :typeidx, do: :funcidx, else: itype

			# Check that the module exists, otherwise try to load if from disk
			with {:ok, mod} <- Map.fetch(imports, imprt.mod),
				{:ok, %{type: ^etype, idx: eidx}} <- Map.fetch(mod.exports, imprt.import) do
				imprt
				|> Map.put(:resolved, true)
				|> Map.put(:module, Map.get(imports, imprt.mod))
				|> Map.put(:exportidx, eidx)
			else
				_ ->
					with {:ok, m} <- load_file("#{imprt.mod}.wasm"),
					{:ok, %{type: ^etype, idx: eidx}} <- Map.fetch(m.exports, imprt.name) do
						imprt
						|> Map.put(:resolved, true)
						|> Map.put(:module, m)
						|> Map.put(:exportidx, eidx)
					else
						_ -> throw("Could not find a module named '#{imprt.mod}'' containing export '#{imprt.import}'")
					end
			end
		end

		# Build the function index; it has two parts:
		#  1. The first part is a list of reference to all
		#     imported functions. They follow the order
		#     they are declared in the `import` section.
		#  2. The second part is a list of references to
		#     functions in the module. They follow the order
		#     that they are declared in the `code` section.
		indices = (resolved # import part
		|> Enum.filter(fn imprt -> imprt.type == :typeidx end)
		|> Enum.map(fn imprt -> %{module: imprt.module, exportidx: imprt.exportidx, name: imprt.import} end)
		) ++ (module.codes # code part
			|> Tuple.to_list
			|> Enum.with_index
			|> Enum.map(fn {_, idx} ->
			%{fidx: idx}
			end)
		)	|> List.to_tuple

		module
		|> Map.put(:imports, List.to_tuple(resolved))
		|> Map.put(:function_index, indices)
	end


	end

	end

	defp get_limits(type, <<p :: binary>>) when type in 0..1 do
		{min, q} = varint(p)
		if type == 1 do
			{max, r} = varint(q)
			{%{min: min, max: max}, r}
		else
			{%{min: min}, q}
	end
	end

	def vec(type, <<payload :: binary>>) when is_atom(type) do
		{size, rest} = varint(payload)
		vec_unfurl(type, {}, size, rest)
	end
	defp vec_unfurl(type, v, 0, r) when is_atom(type), do: {v, r}
	defp vec_unfurl(_, _, n, _) when n < 0, do: raise "Invalid vector index n=#{n} < 0."
	defp vec_unfurl(:indices, v, n, <<payload :: binary>>) do
		{idx, rest} = varint(payload)
		vec_unfurl(:indices, Tuple.append(v, idx), n-1, rest)
	end
	defp vec_unfurl(type, v, n, <<payload :: binary>>) do
		{item, rest} = vec_item type, payload
		vec_unfurl type, Tuple.append(v, item), (n-1), rest
	end

	# Helper function to extract a vector entry based on the type
	defp vec_item(:types, <<@f64type, rest :: binary>>), do: {:f64, rest}
	defp vec_item(:types, <<@f32type, rest :: binary>>), do: {:f32, rest}
	defp vec_item(:types, <<@i64type, rest :: binary>>), do: {:i64, rest}
	defp vec_item(:types, <<@i32type, rest :: binary>>), do: {:i32, rest}
	defp vec_item(:types, <<@resulttype, rest :: binary>>), do: {{}, rest}
	defp vec_item(:types, <<@functype, rest :: binary>>) do
		{args, r1} = vec(:types, rest)
		{result, r2} = vec(:types, r1)
		{{args, result}, r2}
	end
	defp vec_item(:table, <<0x70, type, p::binary>>) when type in 0..1, do: get_limits(type, p)
	defp vec_item(:memory, <<type, p::binary>>) when type in 0..1, do: get_limits(type, p)
	defp vec_item(:import, <<p :: binary>>) do
		{msize, mrest} = varint(p)
		<<mname::binary-size(msize), q::binary>> = mrest
		{isize, irest} = varint(q)
		<<iname::binary-size(isize), q::binary>> = irest
		import_vec_item_type %{mod: mname, import: iname}, q
	end
	defp vec_item(:data, <<0, instr, eb :: binary>>) when instr in [0x23, 0x41] do
		# eb comes from the spec: it contains a constant expression
		# (hence the 0x23 as this has to be i32.const since an offset
		# in 32-bit memory can only be a 32 bit integer) followed by
		# an array of bytes containing the initial state of the memory
		# at that offset.
		# Il y a encore un probleme: c'est pas forcement un int et c'est
		# pas forcement valide
		{offset, <<0xb, initvec_and_rest :: binary>>} = varint eb
		{initsize, r} = varint initvec_and_rest
		<<init :: binary-size(initsize) , rest :: binary>> = r
		{{offset, init, instr == 0x23}, rest}
	end

	defp import_vec_item_type(t, <<0x3, type, constvar, p::binary>>) do
		{Map.merge(t, %{type: :global, const: constvar == 0, valtype: type}), p}
	end
	defp import_vec_item_type(t, <<0x0, p::binary>>) do
		
		{idx, r} = varint(p)
		{Map.merge(t, %{type: :typeidx, index: idx}), r}
	end
	defp import_vec_item_type(t, <<0x2, has_max, p::binary>>) do
		{min, r} = varint(p)
		if has_max == 1 do
			{max, s} = varint(r)
			{Map.merge(t, %{type: :memory, min: min, max: max}), s}
		else
			{Map.merge(t, %{type: :memory, min: min}), r}
		end
	end
	defp import_vec_item_type(t, <<0x1, 0x70, 0, p::binary>>) do
		{m, r} = varint(p)
		{Map.merge(t, %{type: :table, min: m}), r}
	end
	defp import_vec_item_type(t, <<0x1, 0x70, 1, p::binary>>) do
		{min, r} = varint(p)
		{max, s} = varint(r)
		{Map.merge(t, %{type: :table, min: min, max: max}), s}
	end

	defp exportdesc(0), do: :funcidx
	defp exportdesc(1), do: :tableidx
	defp exportdesc(2), do: :memidx
	defp exportdesc(3), do: :globalidx
	def export_vec(<<payload :: binary>>) do
		{size, rest} = varint(payload)
		export_vec_unfurl({}, size, rest)
	end
	defp export_vec_unfurl(v, s, <<payload :: binary>>) when s > 0 do
		{item, rest} = export_vec_item payload
		export_vec_unfurl Tuple.append(v, item), (s-1), rest
	end
	defp export_vec_unfurl(v, 0, r), do: {v, r}
	defp export_vec_item(<<p::binary>>) do
		{size, rest} = varint(p)
		<<name::binary-size(size), type, q::binary>> = rest
		{idx, r} = varint(q)
		{%{export: name, type: exportdesc(type), index: idx}, r}
	end

	defp extract_sections(module, <<>>) do
		module
	end
	# Used to decode the varint size
	defp extract_sections(module, <<type, rest :: binary>>) do
		{size, r} = varint(rest)
		<<content :: binary-size(size), left :: binary>> = r
		extract_sections(module, type, content, left)
	end
	defp extract_sections(module, n, content, rest) do
		module
		|> Map.put(:sections, Map.put(module.sections, n, content))
		|> extract_sections(rest)
	end

	defp check_header(@wasm_header <> <<rest::binary>>) do
		%Windtrap.Module{} |> extract_sections(rest)
	end

	defp decode_custom(module), do: module
	defp decode_types(module) do
		{types, ""} = vec(:types, module.sections[@section_types_id])
		Map.put(module, :types, types)
	end

	defp decode_imports(module) do
		section = module.sections[@section_imports_id]
		unless is_nil(section) do
		{imports, ""} = vec(:import, section)
		Map.put(module, :imports, imports)
		else
			module
		end
	end

	defp decode_functions(module) do
		section = module.sections[@section_function_id]
		unless is_nil(section) do
			{indices, ""} = vec(:indices, section)
		Map.put(module, :functions, indices)
		else
			module
		end
	end

	defp decode_table(module) do
		section = module.sections[@section_table_id]
		unless is_nil(section) do
			{tables, ""} = vec(:table, section)
			Map.put(module, :table, tables)
		else
			module
	end
	end
	defp decode_memory(module) do
		section = module.sections[@section_memory_id]
		unless is_nil(section) do
			{memories, ""} = vec(:memory, section)
			Map.put(module, :memory, memories)
		else
		module
	end
	end

	defp valtype(@i32type), do: :i32
	defp valtype(@i64type), do: :i64
	defp valtype(@f32type), do: :f32
	defp valtype(@f64type), do: :f64
	defp globaltype(0), do: :const
	defp globaltype(1), do: :var
	defp global_vec_item(t, 0, ""), do: t
	defp global_vec_item(t, n, <<p::binary>>) do
		<<vt, mut, q::binary>>= p

		# Disassemble the init code of the global
		{:ok, {dis, _}, r} = Windtrap.Disassembler.disassemble(q, 0, %{})

		# Execute it to get the init value
		[initval|_] = Windtrap.VM.exec(%Windtrap.VM{}, %{code: dis}).stack

		t
		|> Tuple.append(%{type: valtype(vt), mut: globaltype(mut), expr: dis, value: initval})
		|> global_vec_item(n-1, r)
	end
	defp decode_global(module) do
		if Map.has_key?(module.sections, @section_globals_id) do
			section = module.sections[@section_globals_id]
			{nglobals, data} = varint(section)
			globals = global_vec_item {}, nglobals, data
			Map.put(module, :globals, globals)
		else
			module
		end
	end

	defp decode_export(module) do
		section = module.sections[@section_exports_id]
		{exports, ""} = export_vec(section)

		Map.put(module, :exports, exports)
	end

	defp decode_start(module) do
		section = module.sections[@section_start_id]
		unless is_nil(section) do
			{funcidx, ""} = varint(section)
			Map.put(module, :start, funcidx)
		else
			module
		end
	end

	defp vec_element(v, 0, ""), do: {v, ""}
	defp vec_element(v, n, <<p::binary>>) do
		{tidx, q} = varint(p)
		{:ok, expr, r} = Windtrap.Disassembler.disassemble(q, 0, {})
		# Ignore the y* for now
		v
		|> Tuple.append(%{tableidx: tidx, expr: expr, y: []})
		|> vec_element(n-1, r)
	end
	defp decode_element(module) do
		section = module.sections[@section_element_id]
		unless is_nil(section) do
			{nelems, vecdata} = varint(section)
			{elements, ""} = vec_element({}, nelems, vecdata)

			Map.put(module, :elements, elements)
		else
			module
		end
	end

	defp vec_code(v, _, 0, ""), do: v
	defp vec_code(v, offset, n, <<payload::binary>>) do
		{size, r} = varint(payload)
		<<code_and_locals::binary-size(size), left::binary>> = r
		{nlocals, <<r2::binary>>} = varint(code_and_locals)
		<<locals::binary-size(nlocals), code::binary>> = r2
		{:ok, {dis,noffset}, ""} =  Windtrap.Disassembler.disassemble(code, offset, %{})
		vec_code(Tuple.append(v, %{num_locals: nlocals, locals: locals, code: dis}), noffset, n-1, left)
	end
	defp decode_code(module) do
		section = module.sections[@section_code_id]
		unless is_nil(section) do
			{n, vecdata} = varint(section)
		codes = vec_code({}, 0, n, vecdata)
		Map.put(module, :codes, codes)
		else
			module
		end
	end
	defp decode_data(module) do
		section = module.sections[@section_data_id]
		IO.puts inspect section
		unless is_nil(section) do
			{data, ""} = vec(:data, section)
			Map.put(module, :data, data)
		else
			module
		end
	end

end
