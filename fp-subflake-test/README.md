# fp-subflake-test

A test of using subflakes to define inputs via flake-parts's `flakeModules` exports.

## Goal

Add or remove a component from a NixOS configuration by adding or commenting out a single
line in the top level flake.nix.

The goal here is includes removing the *definition* of the module statically in just one line.
That is, lazy evaluation via a `.enable` option is not enough - I want to avoid download, evaluation,
and even thunk definition within Nix's AST.

## Partial Solutions

Once a component is added it can be disabled / removed with a NixOS option or commenting out
an include. This does not fully remove the component - it's dependencies are still listed
as inputs.

This also does not solve the component addition issue - when adding a component the inputs
must be listed (1) and also referenced within `outputs` (2). Additionally configuration
may be required as NixOs options (3).

### Issues

1. Enabling or disabling a feature that depends on inputs requires specifying inputs up front
in the top level flake that are logically relevent only to a module.

  That is, if I want to add a module "foo" to my NixOs configuration, I should not need to care
that it depends on "bar" nor add "bar" to my top level flake.

2. Extra evaluation and version mismatches due to inability to set a flake's inputs' inputs follows
  recursively. See https://github.com/NixOS/nix/pull/6983 and https://github.com/NixOS/nix/pull/6621

  This one is perhaps more fundamentally a philosophy - should the top level configuration be able
to override a dependency's version specification?

### Test Strategy

Use a sub-flake to define a specific input rather than specifying it directly in flake.nix to
enable modularity across inputs.

The goal is to define a top level flake that can somehow enable `nix fmt` to work with `treefmt-nix`
and only require a single line in the top-level `flake.nix` to toggle this component on and off
completely.

The strategy is to create a subflake to modularize:

1. The `imports` definition of `treefmt-nix`.
2. The options to enable `treefmt-nix` and its configuration.
3. Hooking up `nix fmt` to `treefmt-nix`.


### Outcome

It appears that this is not simple to do with flakes, and that this is possibly the closest
working version:

1. `inputs` in a flake must be statically known
2. Thus, we can only "dynamically" include new `inputs` via subflakes
3. Those subflakes introduce their own versioning / dependency problem that might otherwise be avoided in a single repository (via NixOS modules, for example).

In summary, `flake-parts` makes this potential solution doable (being able to specify dependencies elsewhere),
but not convenient (as it requires a *lot* of boilerplate).
