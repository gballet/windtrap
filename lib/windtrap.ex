defmodule Windtrap do
	@moduledoc """
	Documentation for Windtrap.
	"""

	@wasm_header (<<0>> <> "asm" <> << 1 ::little-size(32)>>)

	@section_types_id 1

	@doc """
	Decode a wasm binary.

	## Examples

	  iex> Windtrap.decode(filename)
	  %Windtrap.Module{...}
	"""
	def decode(filename) do
		{:ok, data} = File.read(filename)
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

	defp varint_size(<<x, rest :: binary>>) when x < 128 do
		{x, rest}
	end
	defp varint_size(<<x, rest :: binary>>) when x >= 128 do
		{z, r} = varint_size(rest)
		{x-128 + 128*z, r}
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
		module
	end

	defp decode_imports(module) do
		module
	end

	defp decode_functions(module) do
		module
	end

	defp decode_table(module) do
		module
	end
	defp decode_memory(module), do: module
	defp decode_global(module), do: module
	defp decode_export(module), do: module
	defp decode_start(module), do: module
	defp decode_element(module), do: module
	defp decode_code(module), do: module
	defp decode_data(module), do: module
end
