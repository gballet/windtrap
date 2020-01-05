defmodule Windtrap.Module do
  @moduledoc """
  Represents a WASM module
  """

  # @enforce_keys: [:types]
  defstruct imports: {},
    exports: {},
    types: {},
    function_types: {},   # types of each function implemented by this module
    sections: %{},
    functions: %{},       # List of function descriptors
    function_index: {},   # types of each imported function, followed by those of
			  # functions implemented by this module
    memory: {},
    code: <<>>,
    globals: %{},
    dependencies: %{}     # List of resolved modules, keyed by module name
end
