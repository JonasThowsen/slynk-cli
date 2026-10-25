The current directory is a checkout of cl-json, the JSON encoder and
decoder. We got this bug report:

> **Encoding a decoded document dies with "Help! 11 nested errors"**
>
> Decoding a document and encoding it back fails as soon as objects nest
> three deep:
>
> ```lisp
> (json:decode-json-from-string "{\"a\": {\"b\": {\"c\": \"test\"}}}")
> ;; => ((:A (:B (:C . "test"))))
>
> (json:encode-json-to-string
>  (json:decode-json-from-string "{\"a\": {\"b\": {\"c\": \"test\"}}}"))
> ;; Help! 11 nested errors. SB-KERNEL:*MAXIMUM-ERROR-DEPTH* exceeded.
> ```
>
> I expect `"{\"a\":{\"b\":{\"c\":\"test\"}}}"`. `encode-json-alist-to-string`
> does the same. Two levels, `{"a": {"b": "test"}}`, encode fine. In our
> web server this takes the whole request thread down, and a
> `handler-case` around the call does not catch it.

Find the cause and fix it in the library. Done means: the call above
gives `"{\"a\":{\"b\":{\"c\":\"test\"}}}"`, documents like it (objects
nested in objects, with strings, numbers and booleans as the other
values) decode and encode back to the same JSON however deep they nest, and
cl-json's own test suite (the `cl-json/test` system) passes. Don't change
the tests.

Six tests of that suite fail already, before this bug, and are not part
of it: `JSON-OBJECT`, `JSON-OBJECT-WITH-PROTOTYPE`,
`TEST*JSON-SYMBOLS-PACKAGE*`, `TEST-ENCODE-JSON-CLOS` and
`TEST-ENCODE-JSON-CLOS-MAX-PACKAGE` (SBCL reports a class that is not yet
finalized) and `JSON-BIND-IN-BIND-BUG` (a documented known bug). The rest
must pass.
