defmodule Windtrap.Disassembler do
	@numeric_instructions %{
		0x45 => :i32_eqz,
		0x46 => :i32_eq,
		0x47 => :i32_ne,
		0x48 => :i32_lt_s,
		0x49 => :i32_lt_u,
		0x4A => :i32_gt_s,
		0x4B => :i32_gt_u,
		0x4C => :i32_le_s,
		0x4D => :i32_le_u,
		0x4E => :i32_ge_s,
		0x4F => :i32_ge_u,
		0x50 => :i64_eqz,
		0x51 => :i64_eq,
		0x52 => :i64_ne,
		0x53 => :i64_lt_s,
		0x54 => :i64_lt_u,
		0x55 => :i64_gt_s,
		0x56 => :i64_gt_u,
		0x57 => :i64_le_s,
		0x58 => :i64_le_u,
		0x59 => :i64_ge_s,
		0x5A => :i64_ge_u,
		0x5B => :f32_eq,
		0x5C => :f32_ne,
		0x5D => :f32_lt,
		0x5E => :f32_gt,
		0x5F => :f32_le,
		0x60 => :f32_ge,
		0x61 => :i64_eq,
		0x62 => :i64_ne,
		0x63 => :i64_lt,
		0x64 => :i64_gt,
		0x65 => :i64_le,
		0x66 => :i64_ge_s,
		0x67 => :i32_clz,
		0x68 => :i32_ctz,
		0x69 => :i32_popcnt,
		0x6A => :i32_add,
		0x6B => :i32_sub,
		0x6C => :i32_mul,
		0x6D => :i32_div_s,
		0x6E => :i32_div_u,
		0x6F => :i32_rem_s,
		0x70 => :i32_rem_u,
		0x71 => :i32_and,
		0x72 => :i32_or,
		0x73 => :i32_xor,
		0x74 => :i32_shl,
		0x75 => :i32_shr_s,
		0x76 => :i32_shr_u,
		0x77 => :i32_rotl,
		0x78 => :i32_rotr,
		0x79 => :i64_clz,
		0x7A => :i64_ctz,
		0x7B => :i64_popcnt,
		0x7C => :i64_add,
		0x7D => :i64_sub,
		0x7E => :i64_mul,
		0x7F => :i64_div_s,
		0x80 => :i64_div_u,
		0x81 => :i64_rem_s,
		0x82 => :i64_rem_u,
		0x83 => :i64_and,
		0x84 => :i64_or,
		0x85 => :i64_xor,
		0x86 => :i64_shl,
		0x87 => :i64_shr_s,
		0x88 => :i64_shr_u,
		0x89 => :i64_rotl,
		0x8A => :i64_rotr,
	}

		defp blocktype(0x40), do: :void
	defp blocktype(0x7c), do: :f64
	defp blocktype(0x7d), do: :f32
	defp blocktype(0x7f), do: :i32
	defp blocktype(0x7e), do: :i64

	def disassemble(dis, _, ""), do: dis
	def disassemble(dis, addr, <<0, payload::binary>>), do: disassemble(Map.put(dis, addr, {:unreachable}), addr+1, payload)
	def disassemble(dis, addr, <<1, payload::binary>>), do: disassemble(Map.put(dis, addr, {:nop}), addr+1, payload)
	def disassemble(dis, addr, <<2, payload::binary>>) do
		{bt, rest} = Windtrap.varint_size(payload)
		disassemble(Map.put(dis, addr, {:block, blocktype(bt)}), addr+1, rest)
	end
	def disassemble(dis, addr, <<0xb, payload::binary>>), do: disassemble(Map.put(dis, addr, {:block_return}), addr+1, payload)
	def disassemble(dis, addr, <<0x10, payload::binary>>) do
		{idx, rest} = Windtrap.varint_size(payload)
		disassemble(Map.put(dis, addr, {:call, idx}), addr+String.length(payload)-String.length(rest)+1, rest)
	end
	def disassemble(dis, addr, <<0x1a, payload::binary>>) do
		disassemble(Map.put(dis, addr, {:drop}), addr+1, payload)
	end
	def disassemble(dis, addr, <<0x23, payload::binary>>) do
		{idx, rest} = Windtrap.varint_size(payload)
		disassemble(Map.put(dis, addr, {:get_global, idx}), addr+String.length(payload)-String.length(rest)+1, rest)
	end
	def disassemble(dis, addr, <<0x24, payload::binary>>) do
		{idx, rest} = Windtrap.varint_size(payload)
		disassemble(Map.put(dis, addr, {:set_global, idx}), addr+String.length(payload)-String.length(rest)+1, rest)
	end
	def disassemble(dis, addr, <<const, payload::binary>>) when const in 0x41..0x44 do
		{val, rest} = Windtrap.varint_size(payload)
		sym = %{0x41 => :i32_const, 0x42 => :i64_const, 0x43 => :f32_const, 0x44 => :f64_const}
		disassemble(Map.put(dis, addr, {sym[const], val}), addr+1+String.length(payload)-String.length(rest), rest)
	end
	def disassemble(dis, addr, <<numinstr, payload::binary>>) when numinstr in 0x45..0xBF, do: disassemble(Map.put(dis, addr, {@numeric_instructions[numinstr]}), addr+1, payload)
end
