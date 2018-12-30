defmodule Windtrap.Normalizer do
  import Windtrap.Varint

  @moduledoc """
  Turn a WASM binary format stream into a normalized binary stream
  in which function arguments have their own size. This is useful
  for execuction.
  """

  @doc """
  This is the function that takes as an input the stream of a function's
  body and returns its normalized version, where values aren't
  varint-encoded.

  ## Example

  This example normalizes the binary stream `<<0xc, 3>>` which represents
  `br 3` and the immediate 3 should be normalized to its little-endian 32
  bit representation.

    iex> Windtrap.Normalizer.normalize(<<0xc, 3>>)
    <<0xc, 3, 0, 0, 0>>
  """
  @spec normalize(binary()) :: binary()
  def normalize(input), do: normalize_helper(input, <<>>)

  defp normalize_helper(<<>>, output), do: output
  defp normalize_helper(<<instr, rest :: binary>>, output) when instr in 0x45..0xbf or instr in 0..1 or instr in 0x1a..0x1b or instr == 0x0f do
    normalize_helper(rest, output <> <<instr>>)
  end
  defp normalize_helper(<<instr, rest :: binary>>, output) when instr in 0x20..0x24 or instr in 0x41..0x42 or instr in 0x0c..0x0d or instr == 0x10 do
    width = if instr == 0x42, do: 64, else: 32
    {val, r} = varint rest
    normalize_helper(r, output <> <<instr, val :: integer-little-size(width)>>)
  end
  defp normalize_helper(<<instr, rest :: binary>>, output) when instr in 0x43..0x44 do
    width = if instr == 0x43, do: 32, else: 64
    {val, r} = varint rest
    normalize_helper(r, output <> <<instr, val :: float-little-size(width)>>)
  end
  defp normalize_helper(<<instr, oa_rest :: binary>>, output) when instr in 0x28..0x3e do
    {offset, a_rest} = varint oa_rest
    {align, rest} = varint a_rest
    normalize_helper(rest, output <> <<instr, offset :: integer-little-size(32), align :: integer-little-size(32)>>)
  end
  defp normalize_helper(<<0x11, idx_zero_rest :: binary>>, output) do
    {idx, <<0, rest :: binary>>} = varint idx_zero_rest
    normalize_helper(rest, output <> <<0x11, idx :: integer-little-size(32), 0>>)
  end
  defp normalize_helper(<<5, rest :: binary>>, output) do
    normalize_helper(rest, output <> <<5>>)
  end
  defp normalize_helper(<<0x0b, rest :: binary>>, output) do
    normalize_helper(rest, output <> <<0x0b>>)
  end
  defp normalize_helper(<<instr, rt, rest :: binary>>, output) when instr in 2..4 and (rt == 0x40 or rt in 0x7c..0x7f) do
    normalize_helper(rest, output <> <<instr, rt :: integer-little-size(32)>>)
  end
end
