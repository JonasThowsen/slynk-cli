The current directory is a checkout of local-time, the date and time
library. We got this bug report:

> **29 February 2000 comes out as 1 March**
>
> We store dates of birth with local-time. A customer born on 29 February
> 2000 shows up as born on 1 March 2000:
>
> ```lisp
> (local-time:format-timestring nil (local-time:parse-timestring "2000-02-29")
>                               :format local-time:+iso-8601-date-format+
>                               :timezone local-time:+utc-zone+)
> ;; => "2000-03-01"      expected: "2000-02-29"
>
> (local-time:timestamp-day (local-time:parse-timestring "2000-02-29")
>                           :timezone local-time:+utc-zone+)
> ;; => 1                 expected: 29
> ```
>
> Other leap days, such as 2024-02-29, come out right.

Find the cause and fix it in the library. Done means: the calls above give
the expected results, other dates are not affected, and local-time's own
test suite (the `local-time/test` system) passes. Don't change the tests.
