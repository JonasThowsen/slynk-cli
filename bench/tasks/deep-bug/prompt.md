The current directory is depot, our tool that resolves a project's
dependencies against the package registry and writes its lock (the
`depot` system; its tests are the `depot/tests` system). Ingrid from the
web team sent this:

> Locking the webshop fails, and I can't see why. With the registry
> snapshot in the repository:
>
> ```lisp
> (depot:lock-project "examples/webshop.sexp" (depot:load-registry "registry/"))
> ```
>
> signals
>
> ```
> Cannot resolve the dependencies of webshop: No release of html-escape satisfies ^2.1.0 (template 1.3.0).
> (and 2 other conflicts)
> ```
>
> But html-escape 2.4.1 is in the registry and not yanked, and
> `(depot:satisfies-p "2.4.1" "^2.1.0")` gives T. The blog example locks
> fine. A couple of other projects get older versions of some packages
> than I would expect, but I have no small case for those.

Find the cause and fix the code. Done means: the webshop locks, with
html-escape 2.4.1; every lock has the releases the requirements and the
resolver's preference for newer releases give; and the project's tests
pass. Don't change the tests or the registry.
