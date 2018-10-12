defmodule Windtrap.Module do
	@moduledoc """
	Represents a WASM module
	"""

	# @enforce_keys: [:types]
	defstruct imports: {},
						exports: {},
						types: {},
						# types of each function implemented by this module
						functions: {},
						sections: %{},
						codes: {},
						# types of each imported function, followed by those of
						# functions implemented by this module
						function_index: {},
						memory: {}
end
