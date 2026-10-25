(in-package #:spool)

;;; The server's log: one line per event, with the time, on the stream the
;;; server was started with. Lines from different threads do not mix.

(defvar *log-lock* (sb-thread:make-mutex :name "spool log"))

(defun timestamp ()
  "Returns the time now as hh:mm:ss.mmm."
  (multiple-value-bind (seconds microseconds) (sb-ext:get-time-of-day)
    (multiple-value-bind (second minute hour) (decode-universal-time
                                               (+ seconds (encode-universal-time 0 0 0 1 1 1970 0)))
      (format nil "~2,'0D:~2,'0D:~2,'0D.~3,'0D"
              hour minute second (floor microseconds 1000)))))

(defun write-log (stream control &rest arguments)
  "Writes a line to the log STREAM, unless it is NIL."
  (when stream
    (sb-thread:with-mutex (*log-lock*)
      (format stream "~&~A ~?~%" (timestamp) control arguments)
      (force-output stream))))
