The current directory is logsum, the monthly report of our web shop's
access logs (see its README; the `logsum` system, and its tests are the
`logsum/tests` system). Marit from operations wrote:

> The monthly report has become slow. Reading March's log and making the
> report takes almost a minute on the report server, and traffic is
> growing. We need it in less than 15 seconds. It is the same with the
> sample log:
>
> ```lisp
> (with-open-file (out "march.log" :direction :output)
>   (logsum:write-sample-log out))
>
> (time (with-open-file (in "march.log")
>         (logsum:monthly-report (logsum:read-log in))))
> ;; about 55 seconds
> ```

Make it fast enough: on this machine, reading the sample March log and
making its report must take less than 15 seconds. The report must stay
the same, character for character, for this log and any other, and the
project's tests must pass. Don't change the tests, the sample data or the
format of the report.
