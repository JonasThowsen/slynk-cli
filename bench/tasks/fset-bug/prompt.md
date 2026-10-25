The current directory is a checkout of FSet, the functional collections
library. We got this bug report:

> **Edges go missing from a set of dependency edges**
>
> I use FSet to work with dependency graphs. A node is an ordinary CLOS
> object, and an edge is a cons of two nodes. Some edges vanish when I put
> them in a set, and a map keyed by edges gives me one edge's value when I
> look up another:
>
> ```lisp
> (defclass node () ((name :initarg :name)))
>
> (let* ((app (make-instance 'node :name "app"))
>        (db (make-instance 'node :name "db"))
>        (cache (make-instance 'node :name "cache")))
>   (list (fset:size (fset:set (cons app db) (cons app cache) (cons db cache)))
>         (fset:lookup (fset:map ((cons app db) 1)) (cons app cache))))
> ;; => (2 1)      expected: (3 NIL)
> ```
>
> The edges that disappear seem to be ones that start at the same node.

Find the cause and fix it in the library. Done means: the call above gives
`(3 NIL)`, distinct keys of this kind stay distinct in sets and maps in
general, and FSet's own test suite (`(asdf:test-system :fset)`) passes.
Don't change the tests.
