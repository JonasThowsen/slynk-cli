# spool

A job server for the back office. Clients submit jobs (an export, a
reminder, a checksum) to named queues; each queue has its own workers,
threads that run its jobs one at a time each. Of the jobs waiting in a
queue, the one of the highest priority (0 to 9, 5 by default) runs first,
and of those the one submitted first. A waiting job can be cancelled; a
job that fails can be tried again, by itself (`:attempts`) or on request
(`RETRY`).

Clients talk to the server over TCP, one request per line (see
`src/protocol.lisp`); `spool-client` is a client in Lisp:

```lisp
(defvar *server* (spool:start-server :queues '(("reports" :workers 1)
                                               ("mail" :workers 4))
                                     :port 7700))

(spool-client:with-connection (c :port 7700)
  (let ((id (spool-client:submit c "mail" "echo" '("hello" "world") :priority 7)))
    (spool-client:wait c id)))
;; => :DONE, "hello world"

(spool:stop-server *server*)
```

The same requests can be made in the server's own image, without the
network: `spool:submit`, `spool:wait-for-job`, `spool:cancel-job` and so
on.

The kinds of job are functions of their arguments, strings, that return
the result; an application defines its own with `spool:define-job-kind`.
There are `echo`, `sleep`, `checksum`, `count-words` and `fail` to begin
with. A kind ends a job as failed with `spool:fail`.

The server logs to `*error-output*`, or the stream given as `:log`.

Run the tests with `(asdf:test-system "spool")`.
