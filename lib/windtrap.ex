defmodule Windtrap do
	@moduledoc """
	Documentation for Windtrap.
	"""

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

	@doc """
	Decode a wasm binary.

	## Examples

	  iex> {:ok, %Windtrap.Module{}} = Windtrap.decode(<<0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00, 0x01, 0x09, 0x02, 0x60, 0x02, 0x7F, 0x7F, 0x00, 0x60, 0x00, 0x00, 0x02, 0x13, 0x01, 0x08, 0x65, 0x74, 0x68, 0x65, 0x72, 0x65, 0x75, 0x6D, 0x06, 0x72, 0x65, 0x76, 0x65, 0x72, 0x74, 0x00, 0x00, 0x03, 0x02, 0x01, 0x01, 0x05, 0x03, 0x01, 0x00, 0x01, 0x07, 0x11, 0x02, 0x06, 0x6D, 0x65, 0x6D, 0x6F, 0x72, 0x79, 0x02, 0x00, 0x04, 0x6D, 0x61, 0x69, 0x6E, 0x00, 0x01, 0x0A, 0x13, 0x01, 0x11, 0x00, 0x41, 0x00, 0x41, 0xCD, 0xD7, 0x02, 0x36, 0x02, 0x00, 0x41, 0x00, 0x41, 0x7F, 0x10, 0x00, 0x0B>>)
	  {:ok, %Windtrap.Module{exports: {%{export: "memory", index: 0, type: :memidx}, %{export: "main", index: 1, type: :funcidx}}, functions: {1}, imports: {%{import: "revert", index: 0, mod: "ethereum", type: :typeidx}}, sections: %{1 => <<2, 96, 2, 127, 127, 0, 96, 0, 0>>, 2 => <<1, 8, 101, 116, 104, 101, 114, 101, 117, 109, 6, 114, 101, 118, 101, 114, 116, 0, 0>>, 3 => <<1, 1>>, 5 => <<1, 0, 1>>, 7 => <<2, 6, 109, 101, 109, 111, 114, 121, 2, 0, 4, 109, 97, 105, 110, 0, 1>>, 10 => <<1, 17, 0, 65, 0, 65, 205, 215, 2, 54, 2, 0, 65, 0, 65, 127, 16, 0, 11>>}, types: {{{:i32, :i32}, {}}, {{}, {}}}, codes: {%{code: %{0 => {:"i32.const", 0}, 5 => {:"i32.const", 43981}, 10 => {:"i32.store", 2, 0}, 19 => {:"i32.const", 0}, 24 => {:"i32.const", 127}, 29 => {:call, 0}, 31 => {:block_return}}, locals: "", num_locals: 0}}}}
	"""
	def decode(data) do
		try do
			d = data
			|> decode_header
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
		module
		|> Map.put(:imports, List.to_tuple(resolved))
		|> Map.put(:function_index, indices)
	end

	def varint_size(<<x, rest :: binary>>) when x < 128 do
		{x, rest}
	end
	def varint_size(<<x, rest :: binary>>) when x >= 128 do
		{z, r} = varint_size(rest)
		{x-128 + 128*z, r}
	end

	def vec(<<payload :: binary>>) do
		{size, rest} = varint_size(payload)
		vec_unfurl({}, size, rest)
	end
	defp vec_unfurl(v, s, <<payload :: binary>>) when s > 0 do
		{item, rest} = vec_item payload
		vec_unfurl Tuple.append(v, item), (s-1), rest
	end
	defp vec_unfurl(v, 0, r), do: {v, r}

	defp vec_item(<<0x7c, rest :: binary>>), do: {:f64, rest}
	defp vec_item(<<0x7d, rest :: binary>>), do: {:f32, rest}
	defp vec_item(<<0x7e, rest :: binary>>), do: {:i64, rest}
	defp vec_item(<<0x7f, rest :: binary>>), do: {:i32, rest}
	defp vec_item(<<0x40, rest  :: binary>>), do: {{}, rest}
	defp vec_item(<<0x60, rest  :: binary>>) do
		{args, r1} = vec(rest)
		{result, r2} = vec(r1)
		{{args, result}, r2}
	end

	# TODO simplify this to avoid code duplication
	def import_vec(<<payload :: binary>>) do
		{size, rest} = varint_size(payload)
		import_vec_unfurl({}, size, rest)
	end
	defp import_vec_unfurl(v, s, <<payload :: binary>>) when s > 0 do
		{item, rest} = import_vec_item payload
		import_vec_unfurl Tuple.append(v, item), (s-1), rest
	end
	defp import_vec_unfurl(v, 0, r), do: {v, r}
	defp import_vec_item(<<p::binary>>) do
		{msize, mrest} = varint_size(p)
		<<mname::binary-size(msize), q::binary>> = mrest
		{isize, irest} = varint_size(q)
		<<iname::binary-size(isize), q::binary>> = irest
		import_vec_item_type %{mod: mname, import: iname}, q
	end
	defp import_vec_item_type(t, <<0x3, type, constvar, p::binary>>) do
		{Map.merge(t, %{type: :global, const: constvar == 0, valtype: type}), p}
	end
	defp import_vec_item_type(t, <<0x0, p::binary>>) do
		{idx, r} = varint_size(p)
		{Map.merge(t, %{type: :typeidx, index: idx}), r}
	end
	defp import_vec_item_type(t, <<0x2, has_max, p::binary>>) do
		{min, r} = varint_size(p)
		if has_max == 1 do
			{max, s} = varint_size(r)
			{Map.merge(t, %{type: :memory, min: min, max: max}), s}
		else
			{Map.merge(t, %{type: :memory, min: min}), r}
		end
	end
	defp import_vec_item_type(t, <<0x1, 0x70, 0, p::binary>>) do
		{m, r} = varint_size(p)
		{Map.merge(t, %{type: :table, min: m}), r}
	end
	defp import_vec_item_type(t, <<0x1, 0x70, 1, p::binary>>) do
		{min, r} = varint_size(p)
		{max, s} = varint_size(r)
		{Map.merge(t, %{type: :table, min: min, max: max}), s}
	end

	defp exportdesc(0), do: :funcidx
	defp exportdesc(1), do: :tableidx
	defp exportdesc(2), do: :memidx
	defp exportdesc(3), do: :globalidx
	def export_vec(<<payload :: binary>>) do
		{size, rest} = varint_size(payload)
		export_vec_unfurl({}, size, rest)
	end
	defp export_vec_unfurl(v, s, <<payload :: binary>>) when s > 0 do
		{item, rest} = export_vec_item payload
		export_vec_unfurl Tuple.append(v, item), (s-1), rest
	end
	defp export_vec_unfurl(v, 0, r), do: {v, r}
	defp export_vec_item(<<p::binary>>) do
		{size, rest} = varint_size(p)
		<<name::binary-size(size), type, q::binary>> = rest
		{idx, r} = varint_size(q)
		{%{export: name, type: exportdesc(type), index: idx}, r}
	end

	defp decode_section(module, <<>>) do
		module
	end
	# Used to decode the varint size
	defp decode_section(module, <<type, rest :: binary>>) do
		{size, r} = varint_size(rest)
		<<content :: binary-size(size), left :: binary>> = r
		decode_section(module, type, content, left)
	end
	defp decode_section(module, n, content, rest) do
		module
		|> Map.put(:sections, Map.put(module.sections, n, content))
		|> decode_section(rest)
	end

	defp decode_header(@wasm_header <> <<rest::binary>>) do
		%Windtrap.Module{} |> decode_section(rest)
	end

	defp decode_custom(module), do: module
	defp decode_types(module) do
		{types, ""} = vec(module.sections[@section_types_id])
		Map.put(module, :types, types)
	end

	defp decode_imports(module) do
		section = module.sections[@section_imports_id]
		{imports, ""} = import_vec(section)

		module |> Map.put(:imports, imports)
	end

	defp vec_functions(v, 0, ""), do: v
	defp vec_functions(v, n, <<payload::binary>>) do
		{idx, rest} = varint_size(payload)
		vec_functions(Tuple.append(v, idx), n-1, rest)
	end
	defp decode_functions(module) do
		section = module.sections[@section_function_id]
		{n, vecdata} = varint_size(section)
		indices = vec_functions({}, n, vecdata)
		Map.put(module, :functions, indices)
	end

	defp decode_table(module) do
			module
	end
	defp vec_memory(v, 0, ""), do: v
	defp vec_memory(v, n, <<type, p::binary>>) when type in 0..1 do
		{min, q} = varint_size(p)
		if type == 1 do
			{max, r} = varint_size(q)
			vec_memory Tuple.append(v, %{min: min, max: max}), n-1, r
		else
			vec_memory Tuple.append(v, %{min: min}), n-1, q
		end
	end
	defp decode_memory(module) do
		section = module.sections[@section_memory_id]
		if not is_nil(section) do
			{n, vecdata} = varint_size(section)
			memories = vec_memory({}, n, vecdata)
			Map.put(module, :memory, memories)
		else
		module
	end
	end

	defp valtype(0x7f), do: :i32
	defp valtype(0x7e), do: :i64
	defp valtype(0x7d), do: :f32
	defp valtype(0x7c), do: :f64
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
			{nglobals, data} = varint_size(section)
			globals = global_vec_item {}, nglobals, data
			Map.put(module, :globals, globals)
		else
			module
		end
	end

	defp decode_export(module) do
		section = module.sections[@section_exports_id]
		{exports, ""} = export_vec(section)

		module |> Map.put(:exports, exports)
	end
	defp decode_start(module), do: module
	defp decode_element(module), do: module

	defp vec_code(v, _, 0, ""), do: v
	defp vec_code(v, offset, n, <<payload::binary>>) do
		{size, r} = varint_size(payload)
		<<code_and_locals::binary-size(size), left::binary>> = r
		{nlocals, <<r2::binary>>} = varint_size(code_and_locals)
		<<locals::binary-size(nlocals), code::binary>> = r2
		{:ok, {dis,noffset}, ""} =  Windtrap.Disassembler.disassemble(code, offset, %{})
		vec_code(Tuple.append(v, %{num_locals: nlocals, locals: locals, code: dis}), noffset, n-1, left)
	end
	defp decode_code(module) do
		section = module.sections[@section_code_id]
		{n, vecdata} = varint_size(section)
		codes = vec_code({}, 0, n, vecdata)
		Map.put(module, :codes, codes)
	end
	defp decode_data(module), do: module
end
