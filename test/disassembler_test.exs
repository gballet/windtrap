defmodule DisassemblerTest do
  use ExUnit.Case
  doctest Windtrap.Disassembler

  @sample_func_code <<2, 64, 35, 0, 65, 16, 106, 36, 2, 35, 2, 65, 128, 128, 192, 2, 106, 36, 3, 16, 2, 11, 11>>

  test "disassemble a simple function" do
    assert {dis, 37} = Windtrap.Disassembler.disassemble(@sample_func_code, 0, %{})
    assert Map.size(dis) == 12
  end

  test "disassembled function starts with a :block instruction" do
    {dis, _} = Windtrap.Disassembler.disassemble(@sample_func_code, 0, %{})
    assert {:block, _} = Map.get(dis, 0)
  end

  test "disassembled function ends with a :block_return instruction" do
    {dis, _} = Windtrap.Disassembler.disassemble(@sample_func_code, 0, %{})
    assert {:block_return} = Map.get(dis, Enum.max(Map.keys(dis)))
  end
end
