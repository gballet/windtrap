defmodule Windtrap.Varint do
	def varint(<<x, rest :: binary>>) when x < 128 do
		{x, rest}
	end
	def varint(<<x, rest :: binary>>) when x >= 128 do
		{z, r} = varint(rest)
		{x-128 + 128*z, r}
	end
end
