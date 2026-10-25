# depot

Resolves a project's dependencies against our package registry and
writes the lock file, as Cargo and npm do for theirs.

- `registry/` is a snapshot of the registry: a file per package, with
  its releases and their dependencies.
- `examples/` has two projects, `webshop.sexp` and `blog.sexp`.
- Versions are semantic versions; constraints are the ranges of
  package.json and Cargo.toml (`^1.2.0`, `~1.4.2`, `>=1.0 <3`,
  `1.2.x`, `^1.0.0 || ^2.0.0`), described at the top of
  `src/constraints.lisp`.
- The resolver (`src/resolver.lisp`) chooses the newest releases that
  satisfy every requirement, going back to earlier choices on
  conflicts.

```lisp
(depot:lock-project "examples/blog.sexp" (depot:load-registry "registry/")
                    :output "blog.lock")
```

The packages are `depot.semver` (versions, version sets, constraints),
`depot.registry` (the registry) and `depot` (projects, the resolver,
locks); `depot` exports what a user needs of the other two.

Run the tests with

```lisp
(asdf:test-system "depot")
```
