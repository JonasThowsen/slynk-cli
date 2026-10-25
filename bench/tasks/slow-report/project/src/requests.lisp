(in-package #:logsum)

;;; A request is one line of the web servers' access log, with its fields
;;; separated by tabs:
;;;
;;;   time  ip  method  path  status  bytes  latency-ms  user-agent  referrer
;;;
;;; The time and the strings are kept as the log writes them.

(defstruct (request (:copier nil))
  (time "" :type simple-string)
  (ip "" :type simple-string)
  (method "GET" :type simple-string)
  (path "/" :type simple-string)
  (status 200 :type (integer 100 599))
  (bytes 0 :type (integer 0))
  (latency 0 :type (integer 0))
  (agent "" :type simple-string)
  (referrer "" :type simple-string))

(defun request-seconds (request)
  "Returns the time of REQUEST in seconds."
  (parse-timestamp (request-time request)))

(defun request-day (request)
  "Returns the day of REQUEST."
  (timestamp-day (request-time request)))

;;; Routes: a path decoded and in lower case, without its query and a
;;; slash at the end, with the parts that are ids written as :id, and the
;;; files under /static/ as one route. The shop's paths are not
;;; case-sensitive, and the category pages have Norwegian names, such as
;;; /kategori/st%C3%B8vler for /kategori/støvler.

(defun percent-decode (string)
  "Returns STRING, which is ASCII, with each %XX replaced by the octet XX,
and the octets read as UTF-8."
  (let ((octets (make-array (length string) :element-type '(unsigned-byte 8)
                                            :fill-pointer 0)))
    (loop with index = 0
          while (< index (length string))
          do (if (and (char= (char string index) #\%) (<= (+ index 3) (length string)))
                 (progn
                   (vector-push (parse-integer string :start (1+ index) :end (+ index 3) :radix 16)
                                octets)
                   (incf index 3))
                 (progn
                   (vector-push (char-code (char string index)) octets)
                   (incf index))))
    (sb-ext:octets-to-string octets :external-format :utf-8)))

(defun id-segment-p (segment)
  (and (plusp (length segment)) (every #'digit-char-p segment)))

(defun route-of (path)
  "Returns the route of the request PATH."
  (let ((path (string-downcase
               (string-right-trim "/" (percent-decode (subseq path 0 (position #\? path)))))))
    (cond
      ((string= path "") "/")
      ((eql 0 (search "/static/" path)) "/static/*")
      (t
       (with-output-to-string (route)
         (loop for start = 1 then (1+ slash)
               for slash = (position #\/ path :start start)
               for segment = (subseq path start slash)
               do (write-char #\/ route)
                  (write-string (if (id-segment-p segment) ":id" segment) route)
               while slash))))))

(defun request-route (request)
  "Returns the route of REQUEST."
  (route-of (request-path request)))

;;; Reading and writing the log

(define-condition malformed-log-line (error)
  ((line :initarg :line :reader malformed-log-line-line)
   (reason :initarg :reason :reader malformed-log-line-reason))
  (:report (lambda (condition stream)
             (format stream "Malformed log line (~A): ~S"
                     (malformed-log-line-reason condition)
                     (malformed-log-line-line condition)))))

(defun split-tabs (line)
  (loop for start = 0 then (1+ tab)
        for tab = (position #\Tab line :start start)
        collect (subseq line start tab)
        while tab))

(defun parse-log-line (line)
  "Returns the request of the log LINE. Signals MALFORMED-LOG-LINE if it
is not one."
  (let ((fields (split-tabs line)))
    (unless (= (length fields) 9)
      (error 'malformed-log-line :line line :reason "not nine fields"))
    (destructuring-bind (time ip method path status bytes latency agent referrer) fields
      (flet ((number-field (string what)
               (or (and (plusp (length string))
                        (every #'digit-char-p string)
                        (parse-integer string))
                   (error 'malformed-log-line :line line :reason (format nil "bad ~A" what)))))
        (unless (timestamp-shape-p time)
          (error 'malformed-log-line :line line :reason "bad time"))
        (let ((status (number-field status "status")))
          (unless (<= 100 status 599)
            (error 'malformed-log-line :line line :reason "bad status"))
          (make-request :time time :ip ip :method method :path path :status status
                        :bytes (number-field bytes "bytes")
                        :latency (number-field latency "latency")
                        :agent agent :referrer referrer))))))

(defun format-log-line (request stream)
  "Writes REQUEST to STREAM as a line of the log."
  (format stream "~A~C~A~C~A~C~A~C~D~C~D~C~D~C~A~C~A~%"
          (request-time request) #\Tab (request-ip request) #\Tab
          (request-method request) #\Tab (request-path request) #\Tab
          (request-status request) #\Tab (request-bytes request) #\Tab
          (request-latency request) #\Tab (request-agent request) #\Tab
          (request-referrer request)))

(defun read-log (stream)
  "Returns the requests of the log lines on STREAM, in the order of the
lines. Blank lines are skipped."
  (loop for line = (read-line stream nil)
        while line
        unless (zerop (length line))
          collect (parse-log-line line)))
