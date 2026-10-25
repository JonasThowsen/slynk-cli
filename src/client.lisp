;;;; src/client.lisp -- the command lisp (README.md).  Each call is one
;;;; short connection to the image's Slynk port; the image, src/server.lisp
;;;; in it, keeps all the state.  This file loads no systems, so a call
;;;; starts in a fraction of a second.

(require :sb-bsd-sockets)

(defpackage #:slynk-cli-client
  (:use #:cl))
(in-package #:slynk-cli-client)

(defparameter *sources*
  (make-pathname :name nil :type nil :defaults *load-truename*)
  "The directory of this file and of the image's, src/.")

(defun current-directory ()
  "The current directory, as a directory pathname."
  (let ((pwd (sb-ext:posix-getenv "PWD")))
    (if (and pwd (plusp (length pwd)))
        (pathname (if (char= (char pwd (1- (length pwd))) #\/) pwd (concatenate 'string pwd "/")))
        *default-pathname-defaults*)))

(defun parent (directory)
  (let ((path (pathname-directory directory)))
    (and (rest path)
         (make-pathname :directory (butlast path) :defaults directory))))

(defun git-top (directory)
  "The top of the git work tree DIRECTORY is in, or NIL."
  (let* ((output (make-string-output-stream))
         (process (ignore-errors
                   (sb-ext:run-program "git" (list "-C" (namestring directory)
                                                   "rev-parse" "--show-toplevel")
                                       :search t :output output :error nil))))
    (and process (eql 0 (sb-ext:process-exit-code process))
         (let ((top (string-right-trim '(#\Newline) (get-output-stream-string output))))
           (and (plusp (length top)) (pathname (concatenate 'string top "/")))))))

(defun find-root ()
  "The nearest directory up with a .slynk-cli.sexp, else the top of the git
work tree, else the current directory."
  (let ((here (truename (current-directory))))
    (or (loop for directory = here then (parent directory)
              while directory
              when (probe-file (merge-pathnames ".slynk-cli.sexp" directory))
                return directory)
        (git-top here)
        here)))

(defparameter *root* (find-root)
  "The project's root.")

(defun read-configuration ()
  "The property list of the root's .slynk-cli.sexp, read without evaluation."
  (let ((file (merge-pathnames ".slynk-cli.sexp" *root*)))
    (with-open-file (in file :if-does-not-exist nil)
      (and in
           (let ((configuration
                   (handler-case (with-standard-io-syntax
                                   (let ((*read-eval* nil))
                                     (read in nil nil)))
                     (error (condition)
                       (fail "~a cannot be read: ~a" (namestring file) condition)))))
             (unless (and (listp configuration) (evenp (length configuration))
                          (loop for key in configuration by #'cddr
                                always (member key '(:system :lisp :init))))
               (fail "~a must be a property list of :system, :lisp and :init"
                     (namestring file)))
             configuration)))))

(defparameter *usage* "usage: lisp start [--port N] [SYSTEM]
       lisp stop | status
       lisp eval [FORM | -] [--package P] [--wait S] [--limit S]
       lisp eval --in N:F FORM
       lisp wait N [--wait S]
       lisp abort N
       lisp backtrace N [--from K] [--count C]
       lisp frame N F
       lisp restart N R [FORM...]
       lisp restart-frame N F
       lisp return N F FORM
       lisp compile FILE[:LINE]
       lisp definition NAME
       lisp xref calls|calls-who|references|binds|sets|macroexpands|specializes NAME
       lisp inspect FORM
  (every command but start also takes --port N)")

(define-condition usage-error (error)
  ((message :initarg :message :reader usage-message))
  (:report (lambda (condition stream) (write-string (usage-message condition) stream))))

(defun usage-error (format-control &rest arguments)
  (error 'usage-error :message (apply #'format nil format-control arguments)))

(defun quit (code)
  (finish-output *standard-output*)
  (finish-output *error-output*)
  (sb-ext:exit :code code :abort t))

(defun fail (format-control &rest arguments)
  "Say why on standard error and exit 1."
  (format *error-output* "~&lisp: ~?~%" format-control arguments)
  (quit 1))

;;; What start recorded.

(defun state-directory ()
  "Where start records the image: .slynk-cli/ under the root, or the
directory SLYNK_CLI_STATE names."
  (let ((directory (sb-ext:posix-getenv "SLYNK_CLI_STATE")))
    (if (and directory (plusp (length directory)))
        (pathname (concatenate 'string (string-right-trim "/" directory) "/"))
        (merge-pathnames ".slynk-cli/" *root*))))

(defun state-file (name)
  (merge-pathnames name (state-directory)))

(defun read-state (name)
  "The text start recorded as NAME, or NIL."
  (with-open-file (in (state-file name) :if-does-not-exist nil)
    (and in (read-line in nil))))

(defun write-state (name value)
  (with-open-file (out (ensure-directories-exist (state-file name))
                       :direction :output :if-exists :supersede)
    (format out "~a~%" value)))

(defun alive-p (pid)
  (and pid (probe-file (format nil "/proc/~d/" pid))))

(defun recorded-image ()
  "The port and process of the image start recorded, while it is running."
  (let ((port (ignore-errors (parse-integer (read-state "port"))))
        (pid (ignore-errors (parse-integer (read-state "pid")))))
    (and port (alive-p pid) (values port pid))))

(defun relative-name (file)
  "FILE's name, relative to the root when it is under it."
  (let ((name (namestring file))
        (root (namestring *root*)))
    (if (eql 0 (search root name)) (subseq name (length root)) name)))

;;; Slynk's wire protocol: six hexadecimal digits of length, then that many
;;; octets of UTF-8 text.

(defun connect (port)
  "A stream to 127.0.0.1:PORT, or NIL when nothing answers there."
  (let ((socket (make-instance 'sb-bsd-sockets:inet-socket :type :stream :protocol :tcp)))
    (handler-case
        (progn (sb-bsd-sockets:socket-connect socket #(127 0 0 1) port)
               (sb-bsd-sockets:socket-make-stream socket :input t :output t
                                                  :element-type '(unsigned-byte 8)
                                                  :buffering :full))
      (sb-bsd-sockets:socket-error ()
        (sb-bsd-sockets:socket-close socket)
        nil))))

(defun send-message (stream text)
  (let ((octets (sb-ext:string-to-octets text :external-format :utf-8)))
    (write-sequence (sb-ext:string-to-octets (format nil "~6,'0x" (length octets))) stream)
    (write-sequence octets stream)
    (finish-output stream)))

(defun last-log-lines (count)
  "The last COUNT lines of the image's output."
  (let* ((lines (with-input-from-string (in (log-text))
                  (loop for line = (read-line in nil) while line collect line))))
    (last lines count)))

(defun lost-image (condition)
  "Fail because the connection broke while the image answered: say whether
the image stopped, and with what."
  ;; A process that lost its connections may take a moment to end.
  (loop repeat 30 while (recorded-image) do (sleep 0.1))
  (multiple-value-bind (port pid) (recorded-image)
    (declare (ignore port))
    (if pid
        (fail "the connection to the image broke~@[: ~a~]" condition)
        (fail "the image stopped while answering; the end of its output, in ~a:~%~{  ~a~%~}~
               lisp start starts a new one."
              (relative-name (state-file "image.log")) (last-log-lines 15)))))

(defun receive-octets (stream count)
  (let* ((octets (make-array count :element-type '(unsigned-byte 8)))
         (read (read-sequence octets stream)))
    (when (< read count)
      (lost-image nil))
    octets))

(defun receive-message (stream)
  (let ((length (parse-integer (sb-ext:octets-to-string (receive-octets stream 6)) :radix 16)))
    (sb-ext:octets-to-string (receive-octets stream length) :external-format :utf-8)))

(defun call-image (port request)
  "Send REQUEST to the image on PORT; its answer's text and exit code."
  (let ((stream (or (connect port)
                    (fail "no image answers on port ~d; start one with lisp start" port))))
    (unwind-protect
         (progn
           (send-message stream (with-standard-io-syntax
                                  ;; Readably, SBCL would print a base string,
                                  ;; such as a command-line argument, as #A(...).
                                  (let ((*print-readably* nil))
                                    (format nil "(:emacs-rex (slynk-cli:serve '~s) ~s t 1)"
                                            request "COMMON-LISP-USER"))))
           (loop for message = (handler-case (receive-message stream)
                                 (stream-error (condition) (lost-image condition)))
                 ;; Slynk sends other messages too, such as indentation hints.
                 when (eql 0 (search "(:return " message))
                 do (let ((reply (with-standard-io-syntax
                                   (let ((*read-eval* nil)
                                         (*package* (find-package "KEYWORD")))
                                     (read-from-string message)))))
                      (destructuring-bind (kind (status &optional value) id) reply
                        (declare (ignore kind id))
                        (if (eq status :ok)
                            (return (values-list value))
                            (fail "the image could not answer (~(~a~)); ~
                                   was it started with lisp start?"
                                  status))))))
      (close stream))))

;;; Arguments.

(defun parse-number (text what)
  (or (and text (ignore-errors (parse-integer text)))
      (usage-error "~a needs a number, not ~s" what text)))

(defun parse-arguments (arguments)
  "The positional ARGUMENTS and the options among them, as a property list."
  (let ((positional '())
        (options '()))
    (loop while arguments
          do (let ((argument (pop arguments)))
               (flet ((value () (or (pop arguments) (usage-error "~a needs a value" argument))))
                 (cond ((string= argument "--port")
                        (setf (getf options :port) (parse-number (value) "--port")))
                       ((string= argument "--wait")
                        (setf (getf options :wait) (parse-number (value) "--wait")))
                       ((string= argument "--limit")
                        (setf (getf options :limit) (parse-number (value) "--limit")))
                       ((string= argument "--from")
                        (setf (getf options :from) (parse-number (value) "--from")))
                       ((string= argument "--count")
                        (setf (getf options :count) (parse-number (value) "--count")))
                       ((string= argument "--package")
                        (setf (getf options :package) (value)))
                       ((string= argument "--in")
                        (setf (getf options :in) (value)))
                       ((and (> (length argument) 2) (string= argument "--" :end1 2))
                        (usage-error "unknown option ~a" argument))
                       (t (push argument positional))))))
    (values (nreverse positional) options)))

(defun form-text (positional)
  "The text of the forms: the arguments, or standard input for - or none."
  (if (or (null positional) (equal positional '("-")))
      (with-output-to-string (out)
        (loop for line = (read-line *standard-input* nil)
              while line do (write-line line out)))
      (format nil "~{~a~^ ~}" positional)))

(defun parse-place (text)
  "FILE[:LINE]: the file, made absolute from the current directory, and the line."
  (let* ((colon (position #\: text :from-end t))
         (line (and colon (ignore-errors (parse-integer text :start (1+ colon)))))
         (name (if line (subseq text 0 colon) text))
         (file (probe-file (merge-pathnames name (current-directory)))))
    (unless file
      (fail "no file ~a" name))
    (values (namestring file) line)))

(defun exactly (positional count)
  (unless (= (length positional) count)
    (usage-error "this command takes ~r argument~:p" count))
  positional)

(defun request-for (command positional options)
  "The request for the image."
  (let ((wait (getf options :wait 10)))
    (flet ((number-of (text what) (parse-number text what)))
      (cond
        ((string= command "eval")
         (let ((in (getf options :in)))
           (if in
               (let ((colon (or (position #\: in) (usage-error "--in needs N:F, not ~a" in))))
                 (list :eval-in :id (number-of (subseq in 0 colon) "--in")
                       :frame (number-of (subseq in (1+ colon)) "--in")
                       :text (form-text positional)))
               (list :eval :text (form-text positional) :package (getf options :package)
                     :wait wait :limit (getf options :limit 1800)))))
        ((string= command "wait")
         (list :wait :id (number-of (first (exactly positional 1)) "wait") :wait wait))
        ((string= command "abort")
         (list :abort :id (number-of (first (exactly positional 1)) "abort")))
        ((string= command "backtrace")
         (list :backtrace :id (number-of (first (exactly positional 1)) "backtrace")
               :from (getf options :from 0) :count (getf options :count 20)))
        ((string= command "frame")
         (destructuring-bind (id frame) (exactly positional 2)
           (list :frame :id (number-of id "frame") :frame (number-of frame "frame"))))
        ((string= command "restart")
         (when (< (length positional) 2)
           (usage-error "restart takes N and R, then the forms of its arguments"))
         (list :restart :id (number-of (first positional) "restart")
               :restart (number-of (second positional) "restart")
               :text (format nil "~{~a~^ ~}" (cddr positional)) :wait wait))
        ((string= command "restart-frame")
         (destructuring-bind (id frame) (exactly positional 2)
           (list :restart-frame :id (number-of id "restart-frame")
                 :frame (number-of frame "restart-frame") :wait wait)))
        ((string= command "return")
         (when (< (length positional) 3)
           (usage-error "return takes N, F and a form"))
         (list :return :id (number-of (first positional) "return")
               :frame (number-of (second positional) "return")
               :text (format nil "~{~a~^ ~}" (cddr positional)) :wait wait))
        ((string= command "compile")
         (multiple-value-bind (file line) (parse-place (first (exactly positional 1)))
           (list :compile :file file :line line)))
        ((string= command "definition")
         (list :definition :name (first (exactly positional 1))))
        ((string= command "xref")
         (destructuring-bind (kind name) (exactly positional 2)
           (unless (member kind '("calls" "calls-who" "references" "binds" "sets" "macroexpands"
                                  "specializes")
                           :test #'string=)
             (usage-error "unknown xref ~a" kind))
           (list :xref :kind kind :name name)))
        ((string= command "inspect")
         (list :inspect :text (form-text positional)))
        (t (usage-error "unknown command ~a" command))))))

;;; start, stop and status.

(defun log-text ()
  (with-open-file (in (state-file "image.log") :if-does-not-exist nil)
    (if in
        (let* ((text (make-string (file-length in)))
               (end (read-sequence text in)))
          (subseq text 0 end))
        "")))

(defun top-systems ()
  "The names of the .asd files at the top of the root."
  (sort (mapcar #'pathname-name
                (directory (merge-pathnames "*.asd" *root*) :resolve-symlinks nil))
        #'string<))

(defun default-system (configuration)
  "The configuration's :system, else the system named after the one .asd
file at the top of the root, else NIL."
  (or (getf configuration :system)
      (let ((systems (top-systems)))
        (and (= (length systems) 1) (first systems)))))

(defun init-files (configuration)
  "The configuration's :init files, made absolute from the root."
  (let ((init (getf configuration :init)))
    (mapcar (lambda (name)
              (let ((file (probe-file (merge-pathnames name *root*))))
                (unless file
                  (fail "the :init file ~a does not exist" name))
                (namestring file)))
            (if (listp init) init (list init)))))

(defun image-command (configuration)
  "The program and arguments that start the image."
  (let ((lisp (or (getf configuration :lisp) '("sbcl" "--noinform"))))
    (unless (and (consp lisp) (every #'stringp lisp))
      (fail ":lisp must be a list of strings, such as (\"sbcl\" \"--noinform\")"))
    (values (first lisp)
            (append (rest lisp)
                    (list "--load" (namestring (merge-pathnames "image.lisp" *sources*)))))))

(defun keep-out-of-git ()
  "The state directory keeps itself out of git, so no project has to."
  (let ((file (state-file ".gitignore")))
    (unless (probe-file file)
      (with-open-file (out (ensure-directories-exist file) :direction :output)
        (write-line "*" out)))))

(defun log-line (text prefix)
  "The rest of the first line of TEXT that starts with PREFIX, or NIL."
  (let ((start (search (format nil "~%~a" prefix) (format nil "~%~a" text))))
    (and start
         (subseq text (+ start (length prefix))
                 (or (position #\Newline text :start start) (length text))))))

(defun start (positional options)
  (when (> (length positional) 1)
    (usage-error "start takes one system at most"))
  (multiple-value-bind (port pid) (recorded-image)
    (when port
      (fail "an image is already running on port ~d (process ~d); lisp stop first" port pid)))
  (let* ((configuration (read-configuration))
         (system (or (first positional) (default-system configuration)))
         (log (ensure-directories-exist (state-file "image.log"))))
    (keep-out-of-git)
    (multiple-value-bind (program arguments) (image-command configuration)
      (let* ((environment
               (list* (format nil "SLYNK_CLI_ROOT=~a" (namestring *root*))
                      (format nil "SLYNK_CLI_STATE=~a" (namestring (state-directory)))
                      (format nil "SLYNK_CLI_PORT=~d" (getf options :port 0))
                      (format nil "SLYNK_CLI_SYSTEM=~@[~a~]" system)
                      (format nil "SLYNK_CLI_INIT=~{~a~^~%~}" (init-files configuration))
                      (remove-if (lambda (variable)
                                   (some (lambda (name) (eql 0 (search name variable)))
                                         '("SLYNK_CLI_ROOT=" "SLYNK_CLI_STATE="
                                           "SLYNK_CLI_PORT=" "SLYNK_CLI_SYSTEM="
                                           "SLYNK_CLI_INIT=")))
                                 (sb-ext:posix-environ))))
             (process
               ;; SBCL starts it in a process group of its own, so the
               ;; image outlives the shell that ran lisp start.
               (or (ignore-errors
                    (sb-ext:run-program program arguments
                                        :search t :wait nil :input nil
                                        :directory (namestring *root*)
                                        :environment environment
                                        :output (namestring log)
                                        :if-output-exists :supersede :error :output))
                   (fail "cannot run ~a; is it on PATH?" program)))
             (pid (sb-ext:process-pid process)))
        (write-state "pid" pid)
        (write-state "system" (or system ""))
        (loop repeat 3000
              for text = (log-text)
              for port = (ignore-errors (parse-integer (log-line text "slynk-cli: port ")))
              do (cond ((log-line text "slynk-cli: ready")
                        (write-state "port" port)
                        (let ((failure (search "slynk-cli: loading " text)))
                          (when failure
                            (format t "image on port ~d (process ~d), but ~a~%~
                                       It stays up: fix the file, then ~
                                       lisp eval '(asdf:load-system ~s)'.~%"
                                    port pid
                                    (subseq text (+ failure (length "slynk-cli: "))
                                            (search "slynk-cli: ready" text))
                                    system)
                            (quit 1)))
                        (format t "image on port ~d (process ~d), ~:[no system loaded~;~:*~a ~
                                   loaded~]; its output is in ~a~%"
                                port pid system (relative-name (state-file "image.log")))
                        (let ((systems (top-systems)))
                          (when (and (null system) systems)
                            (format t "The root has ~{~a~^, ~}: lisp eval '(asdf:load-system ~
                                       \"~a\")' loads one, or lisp stop and lisp start NAME.~%"
                                    systems (first systems))))
                        (format t "next: lisp eval FORM~%")
                        (quit 0))
                       ((not (alive-p pid))
                        (format t "the image stopped while starting:~%~a" (log-text))
                        (ignore-errors (delete-file (state-file "pid")))
                        (quit 1)))
                 (sleep 0.2))
        (fail "the image did not load ~a in ten minutes; see ~a" system
              (relative-name (state-file "image.log")))))))

(defun stop ()
  (multiple-value-bind (port pid) (recorded-image)
    (unless port
      (fail "no image is running; start one with lisp start"))
    (sb-ext:run-program "kill" (list (princ-to-string pid)) :search t :wait t)
    (loop repeat 100 while (alive-p pid) do (sleep 0.1))
    (when (alive-p pid)
      (fail "process ~d did not stop" pid))
    (dolist (name '("port" "pid" "system"))
      (ignore-errors (delete-file (state-file name))))
    (format t "stopped the image on port ~d~%" port)
    (quit 0)))

(defun image-port (options)
  "The port to talk to: --port, or the image start recorded."
  (or (getf options :port)
      (recorded-image)
      (fail "no image is running; start one with lisp start")))

(defun main (arguments)
  (handler-case
      (let ((command (or (first arguments) (usage-error "a command is needed"))))
        (multiple-value-bind (positional options) (parse-arguments (rest arguments))
          (cond ((string= command "start") (start positional options))
                ((string= command "stop") (exactly positional 0) (stop))
                (t
                 (let* ((status (string= command "status"))
                        (request (if status
                                     (progn (exactly positional 0) (list :status))
                                     (request-for command positional options)))
                        (port (image-port options)))
                   (multiple-value-bind (text code) (call-image port request)
                     (when status
                       (multiple-value-bind (recorded pid) (recorded-image)
                         (format t "image on port ~d~:[~*~; (process ~d)~]~@[, ~a~]~%"
                                 port (eql recorded port) pid
                                 (and (eql recorded port) (read-state "system")))))
                     (write-string text)
                     (quit code)))))))
    (usage-error (condition)
      (format *error-output* "lisp: ~a~%~a~%" condition *usage*)
      (quit 2))))

(main (rest sb-ext:*posix-argv*))
