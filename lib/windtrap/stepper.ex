defmodule Windtrap.Stepper do
  @moduledoc """
  A set of utility functions to step over a WASM binary: it decodes the
  next instruction, extract its immediates and update the program counter
  to point to the following instruction.

  It is meant to be used as an iterator for various tasks, including
  execution, disassembly and validation.

  ## Example

    iex> Windtrap.Stepper.next(%Windtrap.VM{code: <<1>>}, 1)
    {:ok, %Windtrap.VM{pc: 1, code: <<1>>}, ""}
  """

  def next(vm, instr) when instr <= 1 or instr == 5 or instr == 0x0b or instr == 0x0f or instr in 0x1a..0x1b or instr in 0x45..0xbf, do: {:ok, Map.put(vm, :pc, vm.pc+1), ""}
  def next(vm, instr) when instr in 2..4 or instr in 0xc..0xd or instr == 0x10 or instr in 0x20..0x24 or instr in 0x41..0x44 do
    <<imm :: integer-little-size(32), _ :: binary>> = String.slice(vm.code, vm.pc+1, vm.pc+5)
    {:ok, Map.put(vm, :pc, vm.pc+5), imm}
  end
  def next(vm, instr) when instr in 0x28..0x3e do
    <<imm1 :: integer-little-size(32), imm2 :: integer-little-size(32)>> = String.slice(vm.code, vm.pc+1, vm.pc+9)
    {:ok, Map.put(vm, :pc, vm.pc+9), {imm1, imm2}}
  end
  def next(_vm, instr), do: {:error, "Unknown instruction operand #{instr}"}
end
