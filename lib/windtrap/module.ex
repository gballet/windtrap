defmodule Windtrap.Module do
	@moduledoc """
	Represents a WASM module
	"""

	# @enforce_keys: [:types]
	defstruct imports: {},
						exports: {},
						types: {},
						functions: {},
						sections: %{},
						codes: {},
						functions: {}
end
