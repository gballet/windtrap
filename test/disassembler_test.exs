defmodule DisassemblerTest do
	use ExUnit.Case
  doctest Windtrap.Disassembler

  @sample_func_code <<2, 64, 35, 0, 65, 16, 106, 36, 2, 35, 2, 65, 128, 128, 192, 2, 106, 36, 3, 16, 2, 11, 11>>

  test "disassemble a simple function" do
    assert {:ok, {dis, 41}, ""} = Windtrap.Disassembler.disassemble(@sample_func_code, 0, %{})
    assert map_size(dis) == 12
  end

  test "disassembled function starts with a :block instruction" do
    {:ok, {dis, _}, ""} = Windtrap.Disassembler.disassemble(@sample_func_code, 0, %{})
    assert {:block, _} = Map.get(dis, 0)
  end

  test "disassembled function ends with a :block_return instruction" do
    {:ok, {dis, _}, ""} = Windtrap.Disassembler.disassemble(@sample_func_code, 0, %{})
    assert {:block_return} = Map.get(dis, Enum.max(Map.keys(dis)))
  end

  test "disassemble parametric instructions" do
    for i <- 0x1a..0x1b do
      assert {:ok, {%{0 => t}, 2}, ""} = Windtrap.Disassembler.disassemble(<<i, 0xb>>, 0, %{})
      assert {a} = t
      assert a == :drop || a == :select
    end
  end

  test "disassemble end of block" do
    assert {:ok, {%{0 => {:block_return}}, 1}, ""} = Windtrap.Disassembler.disassemble(<<0xb>>, 0, %{})
  end

  test "disassemble :i32.const" do
    assert {:ok, {%{0 => t}, 6}, ""} = Windtrap.Disassembler.disassemble(<<0x41, 0x4, 0xb>>, 0, %{})
    assert {instr, n} = t
    assert :"i32.const" == instr
  end

  test "disassemble :i64.const" do
    assert {:ok, {%{0 => t}, 10}, ""} = Windtrap.Disassembler.disassemble(<<0x42, 0x4, 0xb>>, 0, %{})
    assert {instr, n} = t
    assert :"i64.const" == instr
  end

  test "disassemble :f32.const" do
    assert {:ok, {%{0 => t}, 6}, ""} = Windtrap.Disassembler.disassemble(<<0x43, 0x4, 0xb>>, 0, %{})
    assert {instr, n} = t
    assert :"f32.const" == instr
  end

  test "disassemble :f64.const" do
    assert {:ok, {%{0 => t}, 10}, ""} = Windtrap.Disassembler.disassemble(<<0x44, 0x4, 0xb>>, 0, %{})
    assert {instr, n} = t
    assert :"f64.const" == instr
  end

  test "disassemble numeric instructions not requiring an opcode" do
    ni = Windtrap.Disassembler.get_numeric_instructions()

    for i <- (Enum.min Map.keys ni)..(Enum.max Map.keys ni) do
      assert {:ok, {%{0 => t}, 2}, ""} = Windtrap.Disassembler.disassemble(<<i,0xb>>, 0, %{})
      assert {a} = t
      assert ni[i] == a
    end
  end
end
