The current directory is a checkout of jzon (`com.inuoe.jzon`), the JSON
reader and writer. We got this bug report:

> **Garbage when stringifying floats**
>
> Thank you for this library! Some floats come out of `stringify` with
> control characters in them:
>
> ```lisp
> (jzon:stringify 1.0d0)       ;; => "^@.0"       expected: "1.0"
> (jzon:stringify 12.0d0)      ;; => "^@1.0"      expected: "12.0"
> (jzon:stringify 123456.0s0)  ;; => "^@12345.0"  expected: "123456.0"
> ```
>
> (`^@` is a NUL character; sometimes it is another odd character.)
> `(jzon:stringify 1.2d0)` gives `"1.2"`, as it should. I'm on the
> latest SBCL.

Find the cause and fix it in the library. Done means: the calls above give
the expected strings, other floats are written as before and read back as
the same number, and jzon's own test suite (the `com.inuoe.jzon-tests`
system) passes. Don't change the tests.
