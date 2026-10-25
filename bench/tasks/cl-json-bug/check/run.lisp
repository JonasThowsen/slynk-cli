;;;; Loads the cl-json in CHECK_DIR, then runs the reproduction and
;;;; cl-json's own tests from their copies in CHECK_WORK. Exits 0 when the
;;;; reproduction passes and no test fails but the six that fail before
;;;; the bug too.

(require :asdf)

(defvar *dir* (uiop:getenv "CHECK_DIR"))
(defvar *work* (uiop:getenv "CHECK_WORK"))

(setf *print-right-margin* 200)

(defun fail (control &rest arguments)
  (format t "~&FAIL: ~?~%" control arguments)
  (finish-output)
  (uiop:quit 1))

(asdf:initialize-source-registry
 `(:source-registry (:tree ,*dir*) :inherit-configuration))
(asdf:initialize-output-translations
 `(:output-translations (,*dir* ,(concatenate 'string *work* "fasl/"))
                        :inherit-configuration))

(defun quietly-load-system (name)
  (handler-case
      (let ((*standard-output* (make-broadcast-stream))
            (*error-output* (make-broadcast-stream)))
        (asdf:load-system name))
    (error (e) (fail "~A does not load: ~A" name e))))

(quietly-load-system :cl-json)
(unless (uiop:subpathp (asdf:system-source-directory :cl-json)
                        (uiop:parse-native-namestring *dir*))
  (fail "cl-json was loaded from ~A, not from the project"
        (asdf:system-source-directory :cl-json)))
(quietly-load-system :fiveam)

;;; The reproduction from the report, and close relatives of it.
(load (concatenate 'string *work* "repro.lisp"))
(let ((failures (funcall (find-symbol "REPRODUCTION-FAILURES" :cl-user))))
  (when failures
    (fail "the reported case still goes wrong:~{~%  ~A~}" failures)))

;;; cl-json's own tests, from the pristine copy, reading their JSON
;;; files from that copy too. These six fail on SBCL before the bug as
;;; well: five because a CLOS class is not yet finalized, one a
;;; documented known bug.
(defparameter *failing-before*
  '("JSON-OBJECT" "JSON-OBJECT-WITH-PROTOTYPE" "TEST*JSON-SYMBOLS-PACKAGE*"
    "TEST-ENCODE-JSON-CLOS" "TEST-ENCODE-JSON-CLOS-MAX-PACKAGE" "JSON-BIND-IN-BIND-BUG"))

(let* ((log (make-string-output-stream))
       (failed
         (handler-case
             (let ((*standard-output* log)
                   (*error-output* log)
                   (*trace-output* log))
               (dolist (file '("package" "testdecoder" "testencoder" "testmisc"))
                 (load (concatenate 'string *work* "t/" file ".lisp")))
               (setf (symbol-value (find-symbol "*JSON-TEST-FILES-PATH*" :json-test))
                     (pathname (concatenate 'string *work* "t/")))
               (let ((results (funcall (find-symbol "RUN" :fiveam)
                                       (find-symbol "JSON" :json-test))))
                 (remove-duplicates
                  (loop for result in results
                        unless (typep result (find-symbol "TEST-PASSED" :fiveam))
                          collect (symbol-name
                                   (funcall (find-symbol "NAME" :fiveam)
                                            (funcall (find-symbol "TEST-CASE" :fiveam) result))))
                  :test #'string=)))
           (error (e) (fail "cl-json's tests signalled an error: ~A" e)))))
  (let ((new (set-difference failed *failing-before* :test #'string=)))
    (when new
      (fail "cl-json's test suite fails:~{~%  ~A~}" new))))

(format t "~&PASS: the reported case works and cl-json's test suite passes~%")
(uiop:quit 0)
