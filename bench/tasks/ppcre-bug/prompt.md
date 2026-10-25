The current directory is a checkout of cl-ppcre, the Perl-compatible regex
library. We got this bug report:

> **Optional group reports a value when it did not match**
>
> I parse durations like `2h 10m` or just `10m` with an optional hours
> part:
>
> ```lisp
> (ppcre:register-groups-bind (hours minutes)
>     ("(?:(\\d+)h)?\\s*(\\d+)m" "10m")
>   (list hours minutes))
> ```
>
> I expect `(NIL "10")`, since there is no hours part in `"10m"`, but I get
> `("1" "10")`. `scan-to-strings` shows the same thing:
>
> ```lisp
> (ppcre:scan-to-strings "(?:(\\d+)h)?\\s*(\\d+)m" "10m")
> ;; => "10m", #("1" "10")      expected: "10m", #(NIL "10")
> ```
>
> `"2h 10m"` works and gives `("2" "10")`. Perl gives `undef` for `$1` on
> `"10m"`.

Find the cause and fix it in the library. Done means: the call above gives
`(NIL "10")`, groups that do not take part in a match are `NIL` in general,
and cl-ppcre's own test suite (the `cl-ppcre/test` system) passes. Don't
change the tests.
