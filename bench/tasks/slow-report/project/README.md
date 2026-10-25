# logsum

The monthly report of the web shop's access logs: for each day the
requests, visitors, sessions, bounces, latency and server errors, with the
day's most requested routes; for the month the visitors who came back, the
busiest hour, and a line for each route.

The web servers write one line per request, with tabs between the fields:
time, IP address, method, path, status, bytes, latency in milliseconds,
user agent and referrer (see `src/requests.lisp`). A visitor is an IP
address; a session is a visitor's requests with less than 30 minutes
between each and the next; a bounce is a session of one request.

```lisp
(with-open-file (in "/var/log/shop/2026-03.log")
  (write-string (logsum:monthly-report (logsum:read-log in))))
```

The real logs have customers' addresses in them and stay on the servers;
for development there is a sample with the same shape, the same for the
same seed:

```lisp
(with-open-file (out "march.log" :direction :output)
  (logsum:write-sample-log out))          ; March 2026, about 740,000 requests

(logsum:make-sample-log :seed 2 :start "2026-02-01" :days 28)   ; the requests themselves
```

Run the tests with `(asdf:test-system "logsum")`.
