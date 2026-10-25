;;;; Loads the local-time in CHECK_DIR, then runs the reproduction and
;;;; local-time's own tests from their copies in CHECK_WORK. Exits 0 when
;;;; both pass.

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

(quietly-load-system :local-time)
(unless (uiop:subpathp (asdf:system-source-directory :local-time)
                        (uiop:parse-native-namestring *dir*))
  (fail "local-time was loaded from ~A, not from the project"
        (asdf:system-source-directory :local-time)))
(quietly-load-system :fiasco)

;;; The reproduction from the report, and close relatives of it.
(load (concatenate 'string *work* "repro.lisp"))
(let ((failures (funcall (find-symbol "REPRODUCTION-FAILURES" :cl-user))))
  (when failures
    (fail "the reported case still goes wrong:~{~%  ~A~}" failures)))

;;; local-time's own tests, from the pristine copy. A few of them read
;;; the clock (NOW) or use the default timezone, which is the machine's
;;; /etc/localtime; binding the default timezone to a fixed zone makes
;;; the latter the same on every machine. The clock tests only check
;;; round trips, so they are deterministic too, and none is skipped.
(let* ((log (make-string-output-stream))
       (passed
         (handler-case
             (let ((*standard-output* log)
                   (*error-output* log))
               (dolist (file '("package" "simple" "comparison" "formatting"
                               "parsing" "timezone"))
                 (load (concatenate 'string *work* "test/" file ".lisp")))
               (let ((local-time:*default-timezone*
                       (local-time:find-timezone-by-location-name "Europe/Oslo")))
                 (funcall (find-symbol "RUN-PACKAGE-TESTS" :fiasco)
                          :package (find-package :local-time.test))))
           (error (e) (fail "local-time's tests signalled an error: ~A" e)))))
  (unless passed
    (let ((lines (remove-if-not (lambda (line) (search "when running" line))
                                (uiop:split-string (get-output-stream-string log)
                                                   :separator '(#\Newline)))))
      (fail "local-time's test suite fails:~{~%  ~A~}"
            (subseq lines 0 (min 10 (length lines)))))))

(format t "~&PASS: the reported case works and local-time's test suite passes~%")
(uiop:quit 0)
