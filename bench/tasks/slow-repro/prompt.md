The current directory is tally, our library for the shops' sales figures
(the `tally` system; its tests are the `tally/tests` system). Kari from
the finance team sent this:

> The figures for a day change after I have looked at the largest sales of
> a period. With the sample database (building it takes a while):
>
> ```lisp
> (defparameter *db* (tally:make-sample-database))
>
> (tally:daily-revenue *db* "S017" "2024-03-03")
> ;; => 4284138
> (tally:revenue-between *db* "S017" "2024-03-01" "2024-03-03")
> ;; => 29597605
>
> (mapcar #'tally:sale-amount
>         (tally:largest-sales *db* "S017" "2024-03-01" "2024-03-03" :count 3))
> ;; => (1349940 968950 935400)
>
> (tally:daily-revenue *db* "S017" "2024-03-03")
> ;; => 320766        but it should still be 4284138
> (tally:revenue-between *db* "S017" "2024-03-01" "2024-03-03")
> ;; => 25634233      but it should still be 29597605
> ```
>
> Nothing was added or voided in between; I only asked for the largest
> sales. The other days of the period look right. We see the same on the
> real data, where the weekly report then disagrees with the daily ones.

Find the cause and fix the code. Done means: in the sequence above, the
last two calls give 4284138 and 29597605, no query changes what later
queries answer, and the project's tests pass. Don't change the tests.
