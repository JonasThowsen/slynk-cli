The current directory is spool, our job server (see its README; the
`spool` system, and its tests are the `spool/tests` system). Ingrid from
operations sent this:

> Now and then a job in the reports queue never runs. WAIT on it never
> returns and STATUS says `queued` for ever, though the queue is not
> paused and its worker is idle. It seems to happen after someone cancels
> a reminder while an export is running. This shows it every time here
> (the exports are `sleep` jobs in this script; the real ones take a few
> minutes):
>
> ```lisp
> (defvar *server* (spool:start-server :queues '(("reports" :workers 1))))
>
> (spool-client:with-connection (c :port (spool:server-port *server*))
>   (let ((export-1 (spool-client:submit c "reports" "sleep" '("1")))
>         (export-2 (spool-client:submit c "reports" "sleep" '("1")))
>         (reminder-1 (spool-client:submit c "reports" "echo" '("reminder" "1"))))
>     (spool-client:wait c export-1)
>     ;; while the second export runs:
>     (loop until (eq (spool-client:status c export-2) :running) do (sleep 0.05))
>     (let ((reminder-2 (spool-client:submit c "reports" "echo" '("reminder" "2"))))
>       (spool-client:cancel c reminder-1)        ; => :CANCELLED
>       (spool-client:wait c reminder-2 :timeout 5))))
> ;; => :TIMEOUT        but it should be :DONE, "reminder 2"
> ```
>
> The server's log has one line about it:
>
> ```
> 09:41:27.112 worker reports-1: job 3 failed: job 3 is cancelled, not queued
> ```
>
> and STATUS of job 3, the reminder we cancelled, says `failed` now.

Find the cause and fix the code. Done means: in the script above the last
WAIT gives `:DONE "reminder 2"` and the cancelled reminder stays
cancelled; in general a cancelled job never runs, every other job runs
once, and the waiting jobs of a queue start in the order of their
priorities, whatever was submitted, cancelled and run before. The
project's tests must pass. Don't change the tests.
