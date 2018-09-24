defmodule Windtrap do
	@moduledoc """
	Documentation for Windtrap.
	"""

	@wasm_header (<<0>> <> "asm" <> << 1 ::little-size(32)>>)

	@section_types_id 1
	@section_imports_id 2
	@section_function_id 3
	@section_code_id 10

	@doc """
	Decode a wasm binary.

	## Examples

	  iex> %Windtrap.Module{} = Windtrap.decode("wasm data")
	  %Windtrap.Module{}
	"""
	def decode(data) do
		data
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
	end

	def decode_file filename do
		{:ok, data} = File.read(filename)
		decode(data)
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
		
		Map.put(module, :imports, imports)
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
	defp decode_memory(module), do: module
	defp decode_global(module), do: module
	defp decode_export(module), do: module
	defp decode_start(module), do: module
	defp decode_element(module), do: module

	defp vec_code(v, _, 0, ""), do: v
	defp vec_code(v, offset, n, <<payload::binary>>) do
		{size, r} = varint_size(payload)
		<<code_and_locals::binary-size(size), left::binary>> = r
		{nlocals, <<r2::binary>>} = varint_size(code_and_locals)
		<<locals::binary-size(nlocals), code::binary>> = r2
		{dis,noffset} =  Windtrap.Disassembler.disassemble(%{}, offset, code)
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
