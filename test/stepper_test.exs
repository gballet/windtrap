defmodule StepperTest do
  use ExUnit.Case
  doctest Windtrap.Stepper
  import Windtrap.Stepper
  alias Windtrap.VM

  @blockret <<2, 64, 0, 0, 0>>
  @unreachable <<1>>
  @i64store32 <<0x3e, 10, 0, 0, 0, 5, 0, 0, 0>>

  test "steps through an instruction taking no immediates" do
    assert {:ok, %VM{pc: 1}, ""} = next(%VM{code: @unreachable}, 1)
  end

  test "steps through an instruction taking one immediate" do
    assert {:ok, %VM{pc: 5}, 64} = next(%VM{code: @blockret}, 2)
  end

  test "steps through an instruction taking two immediates" do
    assert {:ok, %VM{pc: 9}, {10, 5}} = next(%VM{code: @i64store32}, 0x3e)
  end
end
