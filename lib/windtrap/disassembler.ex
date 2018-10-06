defmodule Windtrap.Disassembler do
	@moduledoc """
	This is a helper module to disassemble a binary stream of instructions.

	## Example

		iex> Windtrap.Disassembler.disassemble(<<0x23, 0x8d, 0x5>>, 0, %{})
		{%{0 => {:get_global, 653}}, 5}
	"""

	@numeric_instructions Enum.reduce [
		"i32.eqz", "i32.eq", "i32.ne", "i32.lt_s", "i32.lt_u", "i32.gt_s", "i32.gt_u", "i32.le_s", "i32.le_u", "i32.ge_s", "i32.ge_u",
    "i64.eqz", "i64.eq", "i64.ne", "i64.lt_s", "i64.lt_u", "i64.gt_s", "i64.gt_u", "i64.le_s", "i64.le_u", "i64.ge_s", "i64.ge_u",
		"f32.eq", "f32.ne", "f32.lt", "f32.gt", "f32.le", "f32.ge",
		"f64.eq", "f64.ne", "f64.lt", "f64.gt", "f64.le", "f64.ge",
		"i32.clz", "i32.ctz", "i32.popcnt", "i32.add", "i32.sub", "i32.mul", "i32.div_s", "i32.div_u", "i32.rem_s", "i32.rem_u", "i32.and", "i32.or", "i32.xor", "i32.shl", "i32.shr_s", "i32.shr_u", "i32.rotl", "i32.rotr",
		"i64.clz", "i64.ctz", "i64.popcnt", "i64.add", "i64.sub", "i64.mul", "i64.div_s", "i64.div_u", "i64.rem_s", "i64.rem_u", "i64.and", "i64.or", "i64.xor", "i64.shl" ,"i64.shr_s", "i64.shr_u", "i64.rotl", "i64.rotr",
		"f32.abs", "f32.neg", "f32.ceil", "f32.floor", "f32.trunc", "f32.nearest", "f32.sqrt", "f32.add", "f32.sub", "f32.mul", "f32.div", "f32.min", "f32.max", "f32.copysign",
		"f64.abs", "f64.neg", "f64.ceil", "f64.floor", "f64.trunc", "f64.nearest", "f64.sqrt", "f64.add", "f64.sub", "f64.mul", "f64.div", "f64.min", "f64.max", "f64.copysign",
		"i32.wrap/i64", "i32.trunc_s/f32", "i32.trunc_u/f32", "i32.trunc_s/f64", "i32.trunc_u/f64", "i64.extend_s/i32", "i64.extend_u/i32", "i64.trunc_s/f32", "i64.trunc_u/f32", "i64.trunc_s/f64", "i64.trunc_u/f64", "f32.convert_s/i32", "f32.convert_u/i32", "f32.convert_s/i64", "f32.convert_u/i64", "f32.demote/f64", "f64.convert_s/i32", "f64.convert_u/i32", "f64.convert_s/i64", "f64.convert_u/i64", "f64.promote/f32", "i32.reinterpret/f32", "i64.reinterpret/f64", "f32.reinterpret/i32", "f64.reinterpret/i64",
	], %{}, fn sym, acc -> Map.put(acc, 0x45 + length(Map.keys(acc)), String.to_atom(sym)) end

	# TODO define in a macro that is only valid when building tests
	if Mix.env() == :test do
		def get_numeric_instructions, do: @numeric_instructions
	end

	@memory_instructions Enum.reduce [
		"i32.load", "i64.load", "f32.load", "f64.load", "i32.load8_s", "i32.load8_u", "i32.load16_s", "i32.load16_u", "i64.load8_s", "i64.load8_u", "i64.load16_s", "i64.load16_u", "i64.load32_s", "i64.load32_u", "i32.store", "i64.store", "f32.store",  "f64.store", "i32.store8", "i32.store16", "i64.store8", "i64.store16", "i64.store32", "memory.size", "memory.grow"
	], %{}, fn sym, acc -> Map.put(acc, 0x28 + length(Map.keys(acc)), String.to_atom(sym)) end

	if Mix.env() == :test do
		def get_memory_instructions, do: @memory_instructions
	end

	@parametric_instructions %{0x1a => :drop, 0x1b => :select}

	# @control_instructions %{}

	@variable_instructions Enum.reduce [
		"get_local", "set_local", "tee_local", "get_global", "set_global"
	], %{}, fn sym, acc -> Map.put(acc, 0x20 + length(Map.keys(acc)), String.to_atom(sym)) end

	@const_instructions %{
		0x41 => :"i32.const",
		0x42 => :"i64.const",
		0x43 => :"f32.const",
		0x44 => :"f64.const"
	}

	defp blocktype(0x40), do: :void
	defp blocktype(0x7c), do: :f64
	defp blocktype(0x7d), do: :f32
	defp blocktype(0x7f), do: :i32
	defp blocktype(0x7e), do: :i64

	@doc """
	Disassemble a binary stream of instructions into a human-readable tuple

	## Parameters

	  * `stream` is the binary stream to be decoded.
		* `dis` an empty map, to be filled recursively while decoding the stream.
		* `addr` is the start address for the disassembly. It should be equal to
			the first address past the end of the previous function.

	## Return value

	A tuple containing:

		* a map of all disassembled instructions, keyed by address
		* the first address pas the end of this disassembly, to be
		  used as input in a subsequent call.
	"""
	def disassemble(stream, addr, %{} = dis), do: disassemble_instr(dis, addr, stream)
	def disassemble(_stream, _addr, _dis), do: {:error, "Disassemble should be called with an empty map"}

	defp disassemble_instr(dis, addr, ""), do: {dis, addr}
	defp disassemble_instr(dis, addr, <<0, payload::binary>>), do: disassemble_instr(Map.put(dis, addr, {:unreachable}), addr+1, payload)
	defp disassemble_instr(dis, addr, <<1, payload::binary>>), do: disassemble_instr(Map.put(dis, addr, {:nop}), addr+1, payload)
	defp disassemble_instr(dis, addr, <<2, payload::binary>>) do
		{bt, rest} = Windtrap.varint_size(payload)
		disassemble_instr(Map.put(dis, addr, {:block, blocktype(bt)}), addr+1, rest)
	end
	defp disassemble_instr(dis, addr, <<0xb, payload::binary>>), do: disassemble_instr(Map.put(dis, addr, {:block_return}), addr+1, payload)
	defp disassemble_instr(dis, addr, <<0x10, payload::binary>>) do
		{idx, rest} = Windtrap.varint_size(payload)
		disassemble_instr(Map.put(dis, addr, {:call, idx}), addr+String.length(payload)-String.length(rest)+1, rest)
	end
	defp disassemble_instr(dis, addr, <<param, payload::binary>>) when param in 0x1a..0x1b do
		disassemble_instr(Map.put(dis, addr, {@parametric_instructions[param]}), addr+1, payload)
	end
	defp disassemble_instr(dis, addr, <<varinstr, payload::binary>>) when varinstr in 0x20..0x24 do
		{idx, rest} = Windtrap.varint_size(payload)
		disassemble_instr(Map.put(dis, addr, {@variable_instructions[varinstr], idx}), addr+5, rest)
	end
	defp disassemble_instr(dis, addr, <<const, payload::binary>>) when const in 0x28..0x3E do
		{align, r1} = Windtrap.varint_size(payload)
		{offset, r2} = Windtrap.varint_size(r1)
		Map.put(dis, addr, {@memory_instructions[const], align, offset})
		|> disassemble_instr(addr+9, r2)
	end
	defp disassemble_instr(dis, addr, <<const, payload::binary>>) when const in 0x41..0x44 do
		{val, rest} = Windtrap.varint_size(payload)
		sym = %{0x41 => :i32_const, 0x42 => :i64_const, 0x43 => :f32_const, 0x44 => :f64_const}
		valsize = if rem(const, 2) == 1, do: 4, else: 8
		disassemble_instr(Map.put(dis, addr, {sym[const], val}), addr+1+valsize, rest)
	end
	defp disassemble_instr(dis, addr, <<numinstr, payload::binary>>) when numinstr in 0x45..0xBF do
		disassemble_instr(Map.put(dis, addr, {@numeric_instructions[numinstr]}), addr+1, payload)
	end
end
