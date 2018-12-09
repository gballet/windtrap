defmodule Windtrap.Module do
	@moduledoc """
	Represents a WASM module
	"""

	# @enforce_keys: [:types]
	defstruct imports: {},
						exports: {},
						types: {},
						# types of each function implemented by this module
						function_types: {},
						sections: %{},
						# List of function descriptors
						functions: %{},
						# types of each imported function, followed by those of
						# functions implemented by this module
						function_index: {},
						memory: {},
						code: <<>>,
						globals: %{},
						# List of resolved modules, keyed by module name
						dependencies: %{}
end
