[![CircleCI](https://circleci.com/gh/gballet/windtrap.svg?style=svg)](https://circleci.com/gh/gballet/windtrap)

# windtrap
A WASM VM written in Elixir

## Installation

TODO

## Usage

### iEx

Start iex with mix:

```
$ iex -S mix
```

Then decode a file, e.g. `file.wasm`:

```elixir
Windrap.decode_file("file.wasm")
```

To execute a file, e.g. `file.wasm`:

```elixir
module = Windtrap.decode_file("file.wasm") |> Windtrap.load_module
vm = Windtrap.VM.new([], 0, module)
  |> Windtrap.VM.exec
```

the parameters to `Windtrap.VM.new` are:

  * the list of arguments to the initial function to be executed;
  * the index of the initial function to be executed; and
  * the module

It is possible to pass `Windtrap.load_module` a hash map for module resolution:

  * keys are strings representing the module name as they are declared in the module's `import` section;
  * values are the dependecy `%Windtrap.Module` themselves.

### TODO

## Debugging WASM code

TODO

## TODO

  - [x] Complete section support
  - [ ] Complete execution coverage
  - [ ] Complete test coverage
  - [ ] Code execution
  - [ ] Complete Debugger
  - [ ] Hex.pm release
  - [ ] GenServer version
