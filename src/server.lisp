;;;; src/server.lisp -- the image's side of lisp (README.md, "Commands").
;;;; src/image.lisp loads it into the image lisp start starts, and the
;;;; command calls SERVE over Slynk's wire protocol.
;;;;
;;;; All state lives here, not in a connection: each evaluation runs in a
;;;; thread of its own, and one that enters the debugger stays there, serving
;;;; the commands sent to it, as SLY's debugger loop does.  Frames can only be
;;;; looked into from inside that thread, so a command for a paused
;;;; evaluation is a function the paused thread runs.

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-concurrency))

(defpackage #:slynk-cli
  (:use #:cl)
  (:export #:serve #:*root* #:*state* #:under-root-p #:call-with-project-policy
           #:foreign-pause #:run-in-main-thread #:serve-main-thread))
(in-package #:slynk-cli)

(defparameter *output-lines* 200
  "An answer shows at most this many of the last lines of an output...")
(defparameter *output-characters* (* 16 1024)
  "...and at most this many of its last characters.")
(defparameter *output-kept* (* 100 1024 1024)
  "Characters of one output kept in its file; the rest are counted only.")
(defparameter *value-characters* 2000
  "A printed value is cut after this many characters.")
(defparameter *frames-shown* 20
  "Frames a paused answer shows, and BACKTRACE's default count.")
(defparameter *command-timeout* 60
  "Seconds a request waits for a paused thread to run a command for it.")

(defun directory-from-environment (variable)
  "The directory the environment VARIABLE names, which lisp start sets."
  (let ((name (sb-ext:posix-getenv variable)))
    (if (and name (plusp (length name)))
        (pathname (concatenate 'string (string-right-trim "/" name) "/"))
        (error "~a is not set: start this image with lisp start." variable))))

(defvar *root* (directory-from-environment "SLYNK_CLI_ROOT")
  "The project's root, which files and lines are relative to.")
(defvar *state* (directory-from-environment "SLYNK_CLI_STATE")
  "The directory of the image's records: .slynk-cli/ under the root, or
SLYNK_CLI_STATE.")

(defun output-directory ()
  "Where the output of each evaluation is written."
  (merge-pathnames "output/" *state*))

(defun under-root-p (file)
  "Whether FILE is one of the project's, under the root."
  (eql 0 (search (namestring *root*) (namestring file))))

;;; The project's files compile with at least (debug 3), so the debugger
;;; shows every local of their functions and can restart their frames.
;;; SBCL's minimum policy, which RESTRICT-COMPILER-POLICY sets, is a special
;;; variable: bound around a compilation, it holds for that thread alone, so
;;; a library compiled meanwhile keeps its own policy.

(defun call-with-project-policy (function)
  "Call FUNCTION with at least (debug 3) for what it compiles in this thread."
  (let ((sb-c::*policy-min* sb-c::*policy-min*))
    (sb-ext:restrict-compiler-policy 'debug 3)
    (funcall function)))

(defmethod asdf:perform :around ((operation asdf:compile-op) (file asdf:cl-source-file))
  (if (under-root-p (asdf:component-pathname file))
      (call-with-project-policy #'call-next-method)
      (call-next-method)))

;;; Handles: every value an answer shows is kept, and #@K reads as a form
;;; whose value is the K'th.

(defvar *handles* (make-array 64 :adjustable t :fill-pointer 1)
  "The values answers have shown; #@K is element K.  Element 0 is unused.")
(defvar *handles-lock* (sb-thread:make-mutex :name "lisp handles"))

(defun handle (object)
  "A new handle for OBJECT."
  (sb-thread:with-mutex (*handles-lock*)
    (vector-push-extend object *handles*)))

(defun handle-value (k)
  "The object handle K was given for."
  (if (and (integerp k) (< 0 k (fill-pointer *handles*)))
      (aref *handles* k)
      (error "There is no handle #@~a." k)))

(defun read-handle (stream character argument)
  "#@K: the form (HANDLE-VALUE K)."
  (declare (ignore character argument))
  (let ((k (read stream t nil t)))
    (unless (typep k '(integer 1))
      (error "#@ needs a handle number, not ~s." k))
    `(handle-value ,k)))

(defparameter *readtable-with-handles*
  (let ((readtable (copy-readtable nil)))
    (set-dispatch-macro-character #\# #\@ #'read-handle readtable)
    readtable)
  "The standard readtable with #@K, for what lisp reads.")

;;; Output: written to a file as it comes, with what an answer needs counted.

(defclass output (sb-gray:fundamental-character-output-stream)
  ((file :initarg :file :reader output-file)
   (stream :initarg :stream :reader output-stream)
   (characters :initform 0 :accessor output-characters)
   (lines :initform 0 :accessor output-lines)
   (column :initform 0 :accessor output-column))
  (:documentation "An evaluation's standard, error and trace output."))

(defun make-output (name)
  "A new output written to NAME.txt in the output directory."
  (let ((file (merge-pathnames (make-pathname :name name :type "txt") (output-directory))))
    (ensure-directories-exist file)
    (make-instance 'output :file file
                   :stream (open file :direction :output :if-exists :supersede
                                 :external-format :utf-8))))

(defmethod sb-gray:stream-write-char ((output output) character)
  (when (< (output-characters output) *output-kept*)
    (write-char character (output-stream output)))
  (incf (output-characters output))
  (cond ((char= character #\Newline)
         (setf (output-column output) 0
               (output-lines output) (1+ (output-lines output)))
         ;; Each line reaches the file as it is written, so an answer for
         ;; an evaluation still running shows its output so far.  Only the
         ;; evaluation's own thread writes to or flushes its output.
         (force-output (output-stream output)))
        (t (incf (output-column output))))
  character)

(defmethod sb-gray:stream-line-column ((output output))
  (output-column output))

(defmethod sb-gray:stream-finish-output ((output output))
  (finish-output (output-stream output)))

(defmethod sb-gray:stream-force-output ((output output))
  (force-output (output-stream output)))

(defmethod close ((output output) &key abort)
  (close (output-stream output) :abort abort)
  (call-next-method))

(defun relative-name (file)
  "FILE's name, relative to the root when it is under it."
  (let ((name (namestring file))
        (root (namestring *root*)))
    (if (eql 0 (search root name))
        (subseq name (length root))
        name)))

(defun output-tail (file)
  "The last characters of FILE, enough for an answer."
  (with-open-file (in file :element-type '(unsigned-byte 8))
    (let* ((length (file-length in))
           ;; A UTF-8 character takes four bytes at most.
           (start (max 0 (- length (* 4 *output-characters*))))
           (octets (make-array (- length start) :element-type '(unsigned-byte 8))))
      (file-position in start)
      (read-sequence octets in)
      (sb-ext:octets-to-string octets :external-format '(:utf-8 :replacement #\?)))))

(defun last-lines (text count)
  "The part of TEXT after its last COUNT lines begin."
  (let ((end (if (and (plusp (length text)) (char= (char text (1- (length text))) #\Newline))
                 (1- (length text))
                 (length text))))
    (loop with position = end
          repeat count
          do (setf position (position #\Newline text :end position :from-end t))
          (unless position (return text))
          finally (return (subseq text (1+ position))))))

(defun describe-output (output stream)
  "Write OUTPUT to STREAM as an answer shows it: all of it, or its last part
and where the rest is."
  (let ((characters (output-characters output))
        (lines (output-lines output)))
    (when (plusp characters)
      (let* ((tail (last-lines (output-tail (output-file output)) *output-lines*))
             (tail (if (> (length tail) *output-characters*)
                       (subseq tail (- (length tail) *output-characters*))
                       tail))
             (whole (and (<= characters *output-characters*) (<= lines *output-lines*))))
        (if whole
            (format stream "~&~%output:~%")
            (format stream "~&~%output, the last ~:d of ~:d characters (~:d lines); ~
                            all of it in ~a:~%"
                    (length tail) characters lines (relative-name (output-file output))))
        (write-string tail stream)
        (fresh-line stream)
        (when (> characters *output-kept*)
          (format stream "(output past ~:d characters was not kept)~%" *output-kept*))))))

;;; Printing values and places in the source.

(defun print-value (object)
  "OBJECT printed for an answer, cut at *VALUE-CHARACTERS*."
  (let ((text (handler-case
                  (let ((*print-length* 50) (*print-level* 6) (*print-readably* nil)
                        (*print-pretty* t) (*print-right-margin* 100))
                    (prin1-to-string object))
                (error (condition)
                  (format nil "#<error printing a ~s: ~a>" (type-of object) condition)))))
    (if (> (length text) *value-characters*)
        (format nil "~a… (~:d characters left out)"
                (subseq text 0 *value-characters*) (- (length text) *value-characters*))
        text)))

(defun describe-value (object stream &optional label)
  "Write a line for OBJECT, with a new handle: LABEL #@K = OBJECT."
  (let ((prefix (format nil "~@[~a  ~]#@~d = " label (handle object))))
    (write-string prefix stream)
    ;; Continuation lines of a value printed over several lines line up
    ;; under its first.
    (let ((indent (make-string (length prefix) :initial-element #\Space)))
      (loop for line in (split-lines (print-value object))
            for first = t then nil
            do (unless first (write-string indent stream))
            (write-line line stream)))))

(defun split-lines (text)
  "TEXT's lines."
  (loop for start = 0 then (1+ end)
        for end = (position #\Newline text :start start)
        collect (subseq text start end)
        while end))

(defun file-line (file position)
  "The line of FILE that character POSITION, counted from 0, is on."
  (with-open-file (in file :external-format '(:utf-8 :replacement #\?))
    (loop with line = 1
          repeat position
          for character = (read-char in nil)
          while character
          when (char= character #\Newline) do (incf line)
          finally (return line))))

(defun source-file (name)
  "The file NAME, a source file's name as compiled code records it, is now.
SBCL records its own sources where it was built; they are in its home
directory now."
  (or (probe-file name)
      (let ((built (namestring (translate-logical-pathname "SYS:SRC;"))))
        (and (eql 0 (search built name))
             (probe-file (merge-pathnames (concatenate 'string "src/" (subseq name (length built)))
                                          (sb-int:sbcl-homedir-pathname)))))))

(defun snippet-position (file snippet near)
  "The position of SNIPPET in FILE nearest to NEAR, or NIL."
  (let ((text (read-file-text file)))
    (loop with best = nil
          for start = 0 then (1+ found)
          for found = (search snippet text :start2 start :test #'char-equal)
          while found
          when (or (null best) (< (abs (- found near)) (abs (- best near))))
          do (setf best found)
          finally (return best))))

(defun location-file-and-position (location)
  "The file and the character position, from 0, of a Slynk source LOCATION,
or NIL.  The position is NIL when the location gives none."
  (when (and (consp location) (eq (first location) :location))
    (destructuring-bind (where position &rest hints) (rest location)
      (let ((file (source-file (case (first where)
                                 ((:file :buffer) (second where))
                                 (:buffer-and-file (third where)))))
            (offset (case (first position)
                      ;; A file position from Slynk counts from 1, as
                      ;; Emacs's do.
                      (:position (1- (second position)))
                      (:offset (+ (second position) (third position)))))
            (snippet (second (find :snippet (remove-if-not #'consp hints) :key #'first))))
        (when file
          ;; SBCL's own definitions come with position 1 and a snippet of
          ;; their start; SLY searches for it, and so does this.
          (values file (if (and snippet (or (null offset) (zerop offset)))
                           (snippet-position file snippet (or offset 0))
                           offset)))))))

(defun place (location)
  "FILE:LINE for a Slynk source LOCATION, FILE when it gives no line, or NIL."
  (multiple-value-bind (file position) (location-file-and-position location)
    (when file
      (format nil "~a~@[:~d~]" (relative-name file)
              (and position (plusp position) (file-line file position))))))

;;; Evaluations.

(defstruct (evaluation (:constructor make-evaluation (id text package limit)))
  id text package limit
  thread
  (state :running)                      ; :running :paused :finished :aborted :unreadable :resumed
  foreign                               ; paused in a thread lisp did not start
  main                                  ; runs, or is paused, in the image's main thread
  (values '())                          ; of the last form, when finished
  failure                               ; why it could not be read, or was aborted
  output
  abort-restart
  (commands (sb-concurrency:make-mailbox))
  condition                             ; while paused
  restarts
  bottom                                ; the first frame of lisp's own, while paused
  note                                  ; a command that failed while paused
  (ran 0)                               ; internal time it ran before RUNNING-SINCE
  running-since)

(defvar *evaluations* (make-hash-table) "Every evaluation of this image, by number.")
(defvar *evaluations-lock* (sb-thread:make-mutex :name "lisp evaluations"))
(defvar *count* 0 "The number of the last evaluation.")
(defvar *current-package* (find-package "CL-USER")
  "The package eval reads in, as a REPL's: an evaluation that finishes leaves
its *PACKAGE* here.")
(defvar *evaluation* nil "The evaluation this thread runs.")
(defvar *in-frame-count* (list 0) "Evaluations in a frame so far, for their output files' names.")

(defun evaluations-in (&rest states)
  "The evaluations in one of STATES, by number."
  (sort (sb-thread:with-mutex (*evaluations-lock*)
          (loop for evaluation being the hash-values of *evaluations*
                when (member (evaluation-state evaluation) states)
                collect evaluation))
        #'< :key #'evaluation-id))

(defun find-evaluation (id)
  "Evaluation ID, or an error that names the evaluations there are."
  (or (sb-thread:with-mutex (*evaluations-lock*) (gethash id *evaluations*))
      (error "There is no evaluation ~a; the last one is ~d." id *count*)))

(defun change-state (evaluation state)
  "Move EVALUATION to STATE, keeping account of the time it runs."
  (let ((now (get-internal-real-time)))
    (when (evaluation-running-since evaluation)
      (incf (evaluation-ran evaluation) (- now (evaluation-running-since evaluation))))
    (setf (evaluation-running-since evaluation) (and (eq state :running) now))
    (when (and (evaluation-output evaluation) (open-stream-p (evaluation-output evaluation)))
      (finish-output (evaluation-output evaluation)))
    (setf (evaluation-state evaluation) state)))

(defun seconds-run (evaluation)
  "Seconds EVALUATION has run, its time paused left out."
  (let ((since (evaluation-running-since evaluation)))
    (/ (+ (evaluation-ran evaluation) (if since (- (get-internal-real-time) since) 0))
       internal-time-units-per-second)))

(defun new-evaluation (text package limit)
  "A new evaluation, numbered and kept."
  (sb-thread:with-mutex (*evaluations-lock*)
    (let ((evaluation (make-evaluation (incf *count*) text package limit)))
      (setf (gethash *count* *evaluations*) evaluation))))

(defun start-evaluation (text package limit &optional main)
  "Start evaluating the forms of TEXT in PACKAGE, in a thread of its own; on
the image's main thread when MAIN, which that thread waits for."
  (let ((evaluation (new-evaluation text package (and (not main) limit))))
    (setf (evaluation-main evaluation) main
          (evaluation-output evaluation) (make-output (princ-to-string (evaluation-id evaluation)))
          (evaluation-running-since evaluation) (get-internal-real-time)
          (evaluation-thread evaluation)
          (sb-thread:make-thread #'run-evaluation
                                 :name (format nil "lisp evaluation ~d"
                                               (evaluation-id evaluation))
                                 :arguments (list evaluation)))
    evaluation))

(defmacro with-evaluation-io ((output) &body body)
  "Run BODY with OUTPUT as every output stream, nothing to read, and the
readtable with handles."
  (let ((nothing (gensym "NOTHING")))
    `(let* ((,nothing (make-concatenated-stream))
            (*standard-output* ,output)
            (*error-output* ,output)
            (*trace-output* ,output)
            (*standard-input* ,nothing)
            (*query-io* (make-two-way-stream ,nothing ,output))
            (*debug-io* *query-io*)
            (*terminal-io* *query-io*)
            (*readtable* *readtable-with-handles*)
            (*read-eval* t))
       ,@body)))

(defun run-evaluation (evaluation)
  "The thread of EVALUATION: evaluate its forms; an unhandled condition
pauses it in PAUSE."
  (let ((*evaluation* evaluation)
        (*package* (evaluation-package evaluation))
        (sb-ext:*invoke-debugger-hook* #'pause)
        (*debugger-hook* nil))
    (with-evaluation-io ((evaluation-output evaluation))
      (unwind-protect
           (restart-case
               (progn
                 (setf (evaluation-abort-restart evaluation) (find-restart 'abort))
                 (multiple-value-bind (values unreadable)
                     (if (evaluation-main evaluation)
                         (evaluate-on-main evaluation)
                         (evaluate-forms evaluation))
                   (cond (unreadable
                          (setf (evaluation-failure evaluation) unreadable)
                          (change-state evaluation :unreadable))
                         (t
                          (setf (evaluation-values evaluation) values
                                (evaluation-package evaluation) *package*
                                *current-package* *package*
                                *** **
                                ** *
                                * (first values))
                          (change-state evaluation :finished)))))
             (abort ()
               :report (lambda (stream)
                         (format stream "Abort evaluation ~d." (evaluation-id evaluation)))
               (change-state evaluation :aborted)))
        (close (evaluation-output evaluation))
        ;; Unwound past its own restart, as SBCL's restart that aborts the
        ;; thread does: the thread ends, and so does the evaluation.
        (when (member (evaluation-state evaluation) '(:running :paused))
          (setf (evaluation-failure evaluation) "when its thread was ended")
          (change-state evaluation :aborted))))))

(defun evaluate-forms (evaluation)
  "Read and evaluate the forms of EVALUATION's text in turn, as a REPL does:
an IN-PACKAGE among them changes how the next ones are read.  The values of
the last, or as second value why a form could not be read."
  (with-input-from-string (in (evaluation-text evaluation))
    (let ((values '()))
      (loop (let ((form (handler-case (read in nil in)
                          (error (condition)
                            (return (values nil (princ-to-string condition)))))))
              (when (eq form in)
                (return values))
              (setf values (multiple-value-list (eval form))))))))

;;; The image's main thread.  Some code must run there, such as a C
;;; library's event loop that is not safe to call from another thread.  With
;;; :main in .slynk-cli.sexp the main thread runs the project's function, and
;;; :main-thread-dispatcher names the function of one thunk that runs it
;;; there; without :main, the main thread serves thunks from a queue of its
;;; own.

(defvar *main-thread-queue* (sb-concurrency:make-mailbox :name "lisp main thread"))

(defvar *outer-restarts* '()
  "The restarts around the main thread's work, SBCL's own for loading the
image: a pause there leaves them out, since each would end that work.")

(defun run-in-main-thread (thunk)
  "Run THUNK in the main thread, when it serves the image's own queue."
  (sb-concurrency:send-message *main-thread-queue* thunk))

(defun serve-main-thread ()
  "Run the thunks of the queue in this thread, the main one, one by one."
  (loop (funcall (sb-concurrency:receive-message *main-thread-queue*))))

(defun environment-value (name)
  (let ((value (sb-ext:posix-getenv name)))
    (and value (plusp (length value)) value)))

(defun main-dispatcher ()
  "The function that runs a thunk in the main thread."
  (let ((main (environment-value "SLYNK_CLI_MAIN"))
        (dispatcher (environment-value "SLYNK_CLI_DISPATCHER")))
    (cond (dispatcher
           (let ((symbol (read-symbol dispatcher)))
             (unless (fboundp symbol)
               (error "The main thread's dispatcher ~a is not a function (yet?)." dispatcher))
             (symbol-function symbol)))
          (main
           (error "The main thread runs ~a, so a form gets there only through its own ~
                   dispatcher: name it with :main-thread-dispatcher in .slynk-cli.sexp."
                  main))
          (t #'run-in-main-thread))))

(defun read-symbol (name)
  "The symbol NAME names, such as \"hrt:run-in-main-thread\", read without evaluation."
  (let ((symbol (with-standard-io-syntax
                  (let ((*read-eval* nil))
                    (read-from-string name)))))
    (unless (symbolp symbol)
      (error "~a does not name a function." name))
    symbol))

(defun evaluate-on-main (evaluation)
  "Evaluate EVALUATION's forms in the main thread, as EVALUATE-FORMS does, and
wait for them.  An error there pauses the evaluation in the main thread."
  (let ((reply (sb-concurrency:make-mailbox))
        (package *package*))
    (funcall (main-dispatcher)
             (lambda ()
               (let ((answer '(:unwound)))
                 (unwind-protect
                      (let ((*evaluation* evaluation)
                            (*package* package)
                            (sb-ext:*invoke-debugger-hook* #'pause)
                            (*debugger-hook* nil))
                        (with-evaluation-io ((evaluation-output evaluation))
                          (multiple-value-bind (values unreadable) (evaluate-forms evaluation)
                            (setf answer (list :done values unreadable *package*)))))
                   (sb-concurrency:send-message reply answer)))))
    (destructuring-bind (how &optional values unreadable package)
        (sb-concurrency:receive-message reply)
      (when (eq how :unwound)
        ;; A restart of the main thread's own, such as its event loop's,
        ;; went on past the forms.
        (setf (evaluation-failure evaluation) "when the main thread went on past it")
        (invoke-restart (find-restart 'abort)))
      (setf *package* package)
      (values values unreadable))))

;;; Paused: the debugger of an evaluation's thread.

(defun pause (condition hook)
  "The debugger of an evaluation's thread: wait in it, serving commands."
  (declare (ignore hook))
  (let ((evaluation *evaluation*))
    (slynk-backend:call-with-debugging-environment
     (lambda ()
       (setf (evaluation-condition evaluation) condition
             (evaluation-restarts evaluation)
             (let ((restarts (compute-restarts condition)))
               (if (eq sb-thread:*current-thread* (sb-thread:main-thread))
                   (remove-if (lambda (restart) (member restart *outer-restarts*)) restarts)
                   restarts))
             (evaluation-bottom evaluation) (bottom-frame)
             (evaluation-note evaluation) nil)
       (change-state evaluation :paused)
       (loop (funcall (sb-concurrency:receive-message (evaluation-commands evaluation))))))))

(defun foreign-pause (condition hook)
  "The debugger of every thread lisp did not start, such as the main thread
and a library's: the thread waits in it as a paused evaluation of its own."
  (if *evaluation*
      (pause condition hook)
      (let* ((thread sb-thread:*current-thread*)
             (main (eq thread (sb-thread:main-thread)))
             (evaluation (new-evaluation (format nil "an error in thread ~s"
                                                 (sb-thread:thread-name thread))
                                         *package* nil)))
        (setf (evaluation-foreign evaluation) t
              (evaluation-main evaluation) main
              (evaluation-thread evaluation) thread
              (evaluation-output evaluation) (make-output (princ-to-string
                                                           (evaluation-id evaluation)))
              (evaluation-abort-restart evaluation) (find-restart 'abort condition))
        (let ((*evaluation* evaluation))
          (unwind-protect (pause condition hook)
            (when (open-stream-p (evaluation-output evaluation))
              (close (evaluation-output evaluation)))
            (when (eq (evaluation-state evaluation) :paused)
              (change-state evaluation :resumed)))))))

(defun bottom-frame ()
  "The number of the frame of EVALUATE-FORMS: the frames from there on are
lisp's, not the evaluation's."
  (loop for frame in (slynk-backend:compute-backtrace 0 nil)
        for index from 0
        when (eq (sb-di:debug-fun-name (sb-di:frame-debug-fun frame)) 'evaluate-forms)
        return index
        finally (return index)))

(defun call-guarded (function)
  "FUNCTION's value, or NIL and the condition that would have entered the
debugger: what a paused thread runs for a command must not pause it again."
  (catch 'failed
    (let ((sb-ext:*invoke-debugger-hook*
           (lambda (condition hook)
             (declare (ignore hook))
             (throw 'failed (values nil condition)))))
      (handler-case (values (funcall function) nil)
        (error (condition) (values nil condition))))))

(define-condition no-answer (error)
  ((evaluation :initarg :evaluation :reader no-answer-evaluation)
   (seconds :initarg :seconds :reader no-answer-seconds))
  (:report (lambda (condition stream)
             (format stream "Evaluation ~d did not answer within ~d seconds."
                     (evaluation-id (no-answer-evaluation condition))
                     (no-answer-seconds condition))))
  (:documentation "A paused evaluation's thread is still busy with an earlier command."))

(defun ask (evaluation function &optional (timeout *command-timeout*))
  "FUNCTION's value, run in paused EVALUATION's thread, or an error with the
condition it failed with; NO-ANSWER after TIMEOUT seconds."
  (let ((reply (sb-concurrency:make-mailbox)))
    (sb-concurrency:send-message
     (evaluation-commands evaluation)
     (lambda ()
       (sb-concurrency:send-message reply (multiple-value-list (call-guarded function)))))
    (multiple-value-bind (answer received)
        (sb-concurrency:receive-message reply :timeout timeout)
      (unless received
        (error 'no-answer :evaluation evaluation :seconds timeout))
      (destructuring-bind (value condition) answer
        (when condition
          (error "~a" condition))
        value))))

(defun resume (evaluation function)
  "Make paused EVALUATION go on by FUNCTION, which leaves the debugger, such
as by invoking a restart.  When it does not leave, the evaluation is paused
again with a note saying why."
  ;; FUNCTION transfers control, so it cannot answer; it runs as the next
  ;; command, after this one has answered.  The state is :RUNNING before the
  ;; answer, so the caller waits for what FUNCTION leads to.
  (ask evaluation (lambda ()
                    (sb-concurrency:send-message
                     (evaluation-commands evaluation)
                     (lambda ()
                       (multiple-value-bind (value condition) (call-guarded function)
                         (setf (evaluation-note evaluation)
                               (format nil "That did not resume evaluation ~d: ~a"
                                       (evaluation-id evaluation)
                                       (or condition (and (stringp value) value)
                                           "no reason given")))
                         (change-state evaluation :paused))))
                    ;; A thread lisp did not start goes on with its own work.
                    (change-state evaluation (if (evaluation-foreign evaluation) :resumed :running))
                    t)))

(defun check-paused (evaluation)
  "An error unless EVALUATION is paused."
  (unless (eq (evaluation-state evaluation) :paused)
    (error "Evaluation ~d is not paused; it ~a." (evaluation-id evaluation)
           (state-phrase evaluation))))

(defun check-frame (evaluation frame)
  "An error unless FRAME is one of paused EVALUATION's frames."
  (unless (and (integerp frame) (<= 0 frame) (< frame (evaluation-bottom evaluation)))
    (error "Evaluation ~d has frames 0 to ~d, not ~a." (evaluation-id evaluation)
           (1- (evaluation-bottom evaluation)) frame)))

(defun state-phrase (evaluation)
  "What EVALUATION is doing, as a phrase."
  (ecase (evaluation-state evaluation)
    (:running (format nil "is running (~,1f s)~:[~; in the main thread~]" (seconds-run evaluation)
                      (evaluation-main evaluation)))
    (:paused (format nil "is paused in the debugger~:[~; in the main thread~]"
                     (evaluation-main evaluation)))
    (:resumed "went on: its thread resumed its own work")
    (:finished "has finished")
    (:aborted "was aborted")
    (:unreadable "could not be read")))

(defun one-line (text length)
  "TEXT on one line, cut to LENGTH characters."
  (let ((text (substitute #\Space #\Newline (string-trim '(#\Space #\Tab #\Newline) text))))
    (if (> (length text) length)
        (concatenate 'string (subseq text 0 (1- length)) "…")
        text)))

(defun frame-line (index frame stream)
  "Write FRAME, number INDEX, as a line of a backtrace."
  (format stream "~3d  ~a~@[  ~a~]~%" index
          (one-line (with-output-to-string (out) (slynk-backend:print-frame frame out)) 160)
          (ignore-errors (place (slynk-backend:frame-source-location index)))))

(defun describe-backtrace (evaluation start count stream)
  "Write COUNT frames of paused EVALUATION from frame START.  Runs in its thread."
  (let ((end (min (+ start count) (evaluation-bottom evaluation))))
    (loop for frame in (slynk-backend:compute-backtrace start end)
          for index from start
          do (frame-line index frame stream))
    (when (< end (evaluation-bottom evaluation))
      (format stream "  …  frames ~d to ~d: lisp backtrace ~d --from ~d~%"
              end (1- (evaluation-bottom evaluation)) (evaluation-id evaluation) end))))

(defun describe-paused (evaluation stream)
  "Write what paused EVALUATION shows: the condition, the restarts and the
first frames.  Runs in its thread."
  (let ((condition (evaluation-condition evaluation))
        (id (evaluation-id evaluation)))
    (format stream "evaluation ~d ~a~%~:[~*~;~
                    It is ~a, which lisp did not start: go on with restart-frame, return, or a ~
                    restart it offers. Never abort it: that unwinds frames lisp does not ~
                    know, maybe a C library's.~%~]~@[~a~%~]~%~s: ~a~%"
            id (state-phrase evaluation)
            (evaluation-foreign evaluation) (evaluation-text evaluation)
            (evaluation-note evaluation) (type-of condition)
            (handler-case (princ-to-string condition)
              (error () "(the condition cannot be printed)")))
    (format stream "~%restarts:~%")
    (loop for restart in (evaluation-restarts evaluation)
          for index from 0
          do (format stream "~3d  ~10a  ~a~%" index
                     (if (restart-name restart) (string-downcase (restart-name restart)) "")
                     (substitute #\Space #\Newline
                                 (handler-case (princ-to-string restart)
                                   (error () "(cannot be described)")))))
    (format stream "~%backtrace:~%")
    (describe-backtrace evaluation 0 *frames-shown* stream)))

(defun next-steps (evaluation stream)
  "Write the commands that go on from EVALUATION's state."
  (let ((id (evaluation-id evaluation)))
    (case (evaluation-state evaluation)
      (:paused
       (format stream "~%next: lisp frame ~d F · eval --in ~d:F FORM · ~
                       restart ~d R [FORM...] · restart-frame ~d F · return ~d F FORM~
                       ~:[ · abort ~d~;~]~%"
               id id id id id (main-thread-p evaluation) id))
      (:running
       (format stream "~%next: lisp wait ~d · lisp abort ~d~%" id id)))))

(defun paused-others (evaluation stream)
  "Write the evaluations other than EVALUATION that are paused, since one of
them may hold what EVALUATION waits for."
  (let ((paused (mapcar #'evaluation-id (remove evaluation (evaluations-in :paused)))))
    (when paused
      (format stream "~%paused, and maybe holding what it waits for: ~{evaluation ~d~^, ~}~%"
              paused))))

(defun await (evaluation wait &optional (states '(:running)))
  "Wait at most WAIT seconds for EVALUATION to leave STATES."
  (loop with deadline = (+ (get-internal-real-time) (* wait internal-time-units-per-second))
        while (and (member (evaluation-state evaluation) states)
                   (< (get-internal-real-time) deadline))
        do (sleep 0.01)))

(defun describe-evaluation (evaluation wait)
  "The answer for EVALUATION after waiting at most WAIT seconds for it, and
its exit code."
  (await evaluation wait)
  (let ((id (evaluation-id evaluation)))
    (values
     (with-output-to-string (stream)
       (ecase (evaluation-state evaluation)
         (:finished
          (format stream "evaluation ~d finished~%" id)
          (let ((*package* (evaluation-package evaluation)))
            (if (evaluation-values evaluation)
                (dolist (value (evaluation-values evaluation))
                  (describe-value value stream))
                (format stream "no values~%"))))
         (:unreadable
          (format stream "evaluation ~d: cannot read the forms: ~a~%"
                  id (evaluation-failure evaluation)))
         (:aborted
          (format stream "evaluation ~d was aborted~@[ ~a~]~%" id (evaluation-failure evaluation)))
         (:resumed
          (format stream "evaluation ~d ~a~%" id (state-phrase evaluation)))
         (:running
          (format stream "evaluation ~d is still running (~,1f s)~%" id (seconds-run evaluation))
          (paused-others evaluation stream))
         (:paused
          (write-string (ask evaluation (lambda ()
                                          (with-output-to-string (out)
                                            (describe-paused evaluation out))))
                        stream)))
       (describe-output (evaluation-output evaluation) stream)
       (next-steps evaluation stream))
     (if (member (evaluation-state evaluation) '(:finished :resumed)) 0 1))))

;;; The limit on running time.

(defun watch-limits ()
  "Abort every evaluation that has run longer than its limit, once a second.
An evaluation in the main thread has none.  This thread is lisp's own, so it
must not end or pause: an error checking one evaluation leaves it for the
next second."
  (loop
   (sleep 1)
   (dolist (evaluation (evaluations-in :running))
     (when (ignore-errors (and (evaluation-limit evaluation)
                               (> (seconds-run evaluation) (evaluation-limit evaluation))))
       (setf (evaluation-failure evaluation)
             (format nil "after running ~d s, its limit" (evaluation-limit evaluation)))
       (interrupt-abort evaluation)))))

(defun interrupt-abort (evaluation)
  "Make running EVALUATION's thread invoke its abort restart."
  (let ((restart (evaluation-abort-restart evaluation)))
    (ignore-errors
      (sb-thread:interrupt-thread (evaluation-thread evaluation)
                                  (lambda () (when restart (invoke-restart restart)))))))

(defvar *watcher*
  (sb-thread:make-thread #'watch-limits :name "lisp limits"))

;;; Compiling.

(defun skip-blank (in)
  "Skip whitespace and comments in IN, up to the next form or the end."
  (loop for character = (peek-char nil in nil)
        do (cond ((null character) (return))
                 ((member character '(#\Space #\Tab #\Newline #\Return #\Page))
                  (read-char in))
                 ((char= character #\;) (read-line in nil))
                 ((char= character #\#)
                  (read-char in)
                  (cond ((eql (peek-char nil in nil) #\|)
                         (read-char in)
                         (skip-block-comment in))
                        (t (unread-char #\# in) (return))))
                 (t (return)))))

(defun skip-block-comment (in)
  "Skip the rest of a #| comment, nested ones too."
  (loop with depth = 1
        for previous = nil then character
        for character = (read-char in nil)
        while (and character (plusp depth))
        ;; A character that closes or opens a comment is not the start of
        ;; the next pair.
        do (cond ((and (eql previous #\|) (char= character #\#))
                  (decf depth)
                  (setf character nil))
                 ((and (eql previous #\#) (char= character #\|))
                  (incf depth)
                  (setf character nil)))))

(defun line-start (text line)
  "The position in TEXT where LINE, counted from 1, starts, or NIL."
  (loop with position = 0
        repeat (1- line)
        do (setf position (position #\Newline text :start position))
        (unless position (return nil))
        (incf position)
        finally (return position)))

(defun read-file-text (file)
  "FILE's text."
  (with-open-file (in file :external-format :utf-8)
    (let* ((text (make-string (file-length in)))
           (end (read-sequence text in)))
      (subseq text 0 end))))

(defun toplevel-form-at (file line)
  "The text of the top-level form of FILE that LINE is in, the position it
starts at, and the package the IN-PACKAGE forms before it name."
  (let* ((text (read-file-text file))
         (from (or (line-start text line) (error "~a has no line ~d." (relative-name file) line)))
         (to (or (position #\Newline text :start from) (length text)))
         (*package* (find-package "CL-USER"))
         (*readtable* (copy-readtable nil))
         (*read-eval* t))
    (with-input-from-string (in text)
      (loop
       (skip-blank in)
       (let* ((start (file-position in))
              (form (read in nil in))
              (end (file-position in)))
         (when (or (eq form in) (> start to))
           (error "Line ~d of ~a is not in a top-level form." line (relative-name file)))
         (when (and (<= start to) (> end from))
           (return (values (subseq text start end) start *package*)))
         (when (and (consp form) (eq (first form) 'in-package))
           (setf *package* (or (find-package (second form))
                               (error "~a: no package ~a." (relative-name file)
                                      (second form))))))))))

(defun describe-notes (result stream)
  "Write the notes of a Slynk compilation RESULT that bin/build refuses too,
and whether there were any."
  (destructuring-bind (type notes successp &rest more) result
    (declare (ignore type more))
    (let ((problems (remove-if-not (lambda (note)
                                     (member (getf note :severity)
                                             '(:error :read-error :warning :style-warning)))
                                   notes)))
      (dolist (note problems)
        (format stream "~@[~a  ~]~a: ~a~%"
                (ignore-errors (place (getf note :location)))
                (string-downcase (substitute #\Space #\- (string (getf note :severity))))
                (substitute #\Space #\Newline (getf note :message))))
      (values (or problems (not successp)) (not successp)))))

;;; Slynk's functions read and print in the package and readtable that a
;;; request from SLY binds, in *BUFFER-PACKAGE* and *BUFFER-READTABLE*;
;;; lisp's requests bind them the same way.

(defun compiling (file function)
  "Call FUNCTION, which compiles FILE, under the project's policy when FILE
is the project's."
  (if (under-root-p file)
      (call-with-project-policy function)
      (funcall function)))

(defun compile-form-at (file line)
  "Compile the top-level form of FILE that LINE is in, as C-c C-c."
  (multiple-value-bind (text start package) (toplevel-form-at file line)
    (let* ((name (namestring file))
           (result (let ((slynk::*buffer-package* package)
                         (slynk:*buffer-readtable* (copy-readtable nil)))
                     (compiling file
                       (lambda ()
                         (slynk:compile-string-for-emacs
                          text name `((:position ,start) (:line ,(file-line file start) 1))
                          name nil))))))
      (answer-compiled result (format nil "the form at ~a:~d" (relative-name file)
                                      (file-line file start))))))

(defun compile-whole-file (file)
  "Compile FILE and load it, as C-c C-k."
  (let ((result (compiling file
                  (lambda () (slynk:compile-file-for-emacs (namestring file) t)))))
    ;; SLY loads the compiled file from Emacs once Slynk has compiled it.
    (destructuring-bind (type notes successp duration loadp fasl) result
      (declare (ignore type notes duration))
      (when (and successp loadp fasl)
        (load fasl)))
    (answer-compiled result (relative-name file))))

(defun answer-compiled (result what)
  "The answer for compiling WHAT with Slynk's RESULT, and its exit code."
  (let (problems failed)
    (let ((notes (with-output-to-string (stream)
                   (multiple-value-setq (problems failed) (describe-notes result stream)))))
      (values (format nil "~:[compiled~;could not compile~] ~a~%~a" failed what notes)
              (if problems 1 0)))))

;;; Finding.

(defun describe-locations (entries stream)
  "Write ENTRIES, Slynk's (NAME LOCATION) lists, one a line."
  (dolist (entry entries)
    (destructuring-bind (name location) entry
      (format stream "~a  ~a~%" name
              (or (ignore-errors (place location))
                  (if (eq (first location) :error)
                      (format nil "(~a)" (second location))
                      "(no source)"))))))

(defun answer-definition (name)
  "Where NAME is defined."
  (let ((entries (let ((slynk::*buffer-package* *current-package*))
                   (slynk:find-definitions-for-emacs name))))
    (if entries
        (values (with-output-to-string (stream) (describe-locations entries stream)) 0)
        (values (format nil "no definition of ~a~%" name) 1))))

(defun answer-xref (kind name)
  "The xref of KIND for NAME."
  (let ((entries (let ((slynk::*buffer-package* *current-package*))
                   (slynk:xref (intern (string-upcase kind) :keyword) name))))
    (cond ((eq entries :not-implemented)
           (values (format nil "xref ~a is not available~%" kind) 1))
          (entries
           (values (with-output-to-string (stream) (describe-locations entries stream)) 0))
          (t
           (values (format nil "nothing found: xref ~a ~a~%" kind name) 0)))))

;;; Inspecting.

(defun read-forms-text (text)
  "The forms of TEXT, read in the current package with handles."
  (let ((*package* *current-package*)
        (*readtable* *readtable-with-handles*)
        (*read-eval* t))
    (with-input-from-string (in text)
      (loop for form = (read in nil in)
            until (eq form in)
            collect form))))

(defun answer-inspect (text)
  "The parts of the value of TEXT's last form, each with a handle, as SLY's
inspector shows them."
  (let* ((object (let ((*package* *current-package*))
                   (first (last (mapcar #'eval (read-forms-text text))))))
         (inspected (slynk::inspect-object object))
         (*package* *current-package*))
    (values
     (with-output-to-string (stream)
       (format stream "#@~d = ~a~%~%" (handle object) (getf inspected :title))
       (dolist (part (first (getf inspected :content)))
         (cond ((stringp part) (write-string part stream))
               ((eq (first part) :value)
                (format stream "#@~d = ~a" (handle (slynk:inspector-nth-part (third part)))
                        (second part)))
               ((eq (first part) :label) (write-string (second part) stream))
               ((eq (first part) :action) (format stream "[~a]" (second part)))))
       (fresh-line stream))
     0)))

;;; Requests.

(defun evaluation-for (id)
  "Evaluation ID, which must be paused."
  (let ((evaluation (find-evaluation id)))
    (check-paused evaluation)
    evaluation))

(defun answer-eval-in (id frame text wait)
  "Evaluate TEXT in FRAME of paused evaluation ID, waiting at most WAIT
seconds for it."
  (let ((evaluation (evaluation-for id)))
    (ask evaluation (lambda () (check-frame evaluation frame)))
    (handler-case (eval-in-frame evaluation frame text wait)
      (no-answer ()
        (error "The form is still running in frame ~d of evaluation ~d after ~d s, and goes ~
                on there; the evaluation answers nothing else until it ends.~%~
                lisp abort ~d ends the evaluation." frame id wait id))
      (error (condition)
        (error "In frame ~d of evaluation ~d: ~a~%Evaluation ~d is still paused."
               frame id condition id)))))

(defun eval-in-frame (evaluation frame text wait)
  (let* ((id (evaluation-id evaluation))
         (output (make-output (format nil "~d-frame-~d-~d" id frame
                                      (sb-ext:atomic-incf (car *in-frame-count*)))))
         (values
          (unwind-protect
               (ask evaluation
                    (lambda ()
                      (with-evaluation-io (output)
                        (let ((*package* (or (slynk-backend:frame-package frame) *package*)))
                          (let ((values '()))
                            (dolist (form (let ((*current-package* *package*))
                                            (read-forms-text text))
                                     values)
                              (setf values (multiple-value-list
                                            (slynk-backend:eval-in-frame form frame))))))))
                    wait)
            (finish-output output))))
    (values (with-output-to-string (stream)
              (format stream "in frame ~d of evaluation ~d, still paused~%" frame id)
              (if values
                  (dolist (value values) (describe-value value stream))
                  (format stream "no values~%"))
              (describe-output output stream)
              (close output))
            0)))

(defun answer-frame (id frame)
  "Frame FRAME of paused evaluation ID: its call, source and locals."
  (let ((evaluation (evaluation-for id)))
    (values
     (ask evaluation
          (lambda ()
            (check-frame evaluation frame)
            (with-output-to-string (stream)
              (format stream "frame ~d of evaluation ~d~%" frame id)
              (frame-line frame (first (slynk-backend:compute-backtrace frame (1+ frame))) stream)
              (let ((locals (slynk-backend:frame-locals frame)))
                (if locals
                    (progn (format stream "~%locals:~%")
                           (dolist (local locals)
                             (describe-value (getf local :value) stream
                                             (format nil "  ~(~a~)" (getf local :name)))))
                    (format stream "~%no locals~%")))
              (format stream "~%restartable: ~:[no~;yes~]~%"
                      (slynk-backend:frame-restartable-p
                       (first (slynk-backend:compute-backtrace frame (1+ frame))))))))
     0)))

(defun answer-backtrace (id from count)
  (let ((evaluation (evaluation-for id)))
    (values (ask evaluation (lambda ()
                              (with-output-to-string (stream)
                                (describe-backtrace evaluation from count stream))))
            0)))

(defun answer-restart (id restart text wait)
  "Invoke restart number RESTART of paused evaluation ID with the values of
TEXT's forms."
  (let* ((evaluation (evaluation-for id))
         (chosen (or (nth restart (evaluation-restarts evaluation))
                     (error "Evaluation ~d has restarts 0 to ~d, not ~a." id
                            (1- (length (evaluation-restarts evaluation))) restart))))
    (let ((forms (read-forms-text text)))
      (resume evaluation (lambda () (apply #'invoke-restart chosen (mapcar #'eval forms)))))
    (describe-evaluation evaluation wait)))

(defun answer-restart-frame (id frame wait)
  (let ((evaluation (evaluation-for id)))
    (ask evaluation (lambda ()
                      (check-frame evaluation frame)
                      (unless (slynk-backend:frame-restartable-p
                               (first (slynk-backend:compute-backtrace frame (1+ frame))))
                        (error "Frame ~d cannot be restarted; it was compiled without (debug 2)?"
                               frame))))
    (resume evaluation (lambda () (slynk-backend:restart-frame frame)))
    (describe-evaluation evaluation wait)))

(defun answer-return (id frame text wait)
  (let ((evaluation (evaluation-for id)))
    (ask evaluation (lambda () (check-frame evaluation frame)))
    (let ((forms (read-forms-text text)))
      (resume evaluation (lambda () (slynk-backend:return-from-frame frame `(progn ,@forms)))))
    (describe-evaluation evaluation wait)))

(defun main-thread-p (evaluation)
  "Whether EVALUATION runs, or is paused, in a thread abort must not unwind:
the main thread, or one lisp did not start."
  (or (evaluation-main evaluation) (evaluation-foreign evaluation)))

(defun answer-abort (id)
  (let ((evaluation (find-evaluation id)))
    (when (and (main-thread-p evaluation) (member (evaluation-state evaluation) '(:running :paused)))
      (error "Evaluation ~d ~a, which lisp did not start; abort would unwind frames below it ~
              that lisp does not know, maybe a C library's, and leave the thread broken. ~
              ~:[It ends when its forms return~;Go on with lisp restart-frame ~d F, lisp return ~
              ~d F FORM, or a restart it offers: lisp restart ~d R~]."
             id (state-phrase evaluation) (eq (evaluation-state evaluation) :paused) id id id))
    ;; Interrupted, not sent a command: a paused evaluation's thread may be
    ;; busy with a form evaluated in a frame, and its abort restart is on
    ;; its stack either way.
    (if (member (evaluation-state evaluation) '(:running :paused))
        (interrupt-abort evaluation)
        (error "Evaluation ~d ~a." id (state-phrase evaluation)))
    (await evaluation 10 '(:running :paused))
    (values (format nil "evaluation ~d ~a~%" id (state-phrase evaluation))
            (if (eq (evaluation-state evaluation) :aborted) 0 1))))

(defun answer-status ()
  (let ((open (evaluations-in :running :paused)))
    (values
     (with-output-to-string (stream)
       (format stream "package ~a~%" (package-name *current-package*))
       (if open
           (dolist (evaluation open)
             (format stream "evaluation ~d ~a: ~a~%" (evaluation-id evaluation)
                     (state-phrase evaluation)
                     (one-line (evaluation-text evaluation) 60)))
           (format stream "no evaluation is running or paused~%")))
     0)))

(defun answer (command &rest arguments)
  "The answer for lisp's COMMAND, and its exit code."
  (flet ((package-named (name)
           (if name
               (or (find-package (string-upcase name)) (error "There is no package ~a." name))
               *current-package*)))
    (destructuring-bind (&key text package (wait 10) (limit 1800) id frame restart (from 0)
                              (count *frames-shown*) file line kind name main)
        arguments
      (ecase command
        (:eval (when main (main-dispatcher))
               (describe-evaluation (start-evaluation text (package-named package) limit main)
                                    wait))
        (:eval-in (answer-eval-in id frame text wait))
        (:wait (describe-evaluation (find-evaluation id) wait))
        (:abort (answer-abort id))
        (:backtrace (answer-backtrace id from count))
        (:frame (answer-frame id frame))
        (:restart (answer-restart id restart text wait))
        (:restart-frame (answer-restart-frame id frame wait))
        (:return (answer-return id frame text wait))
        (:compile (if line (compile-form-at file line) (compile-whole-file file)))
        (:definition (answer-definition name))
        (:xref (answer-xref kind name))
        (:inspect (answer-inspect text))
        (:status (answer-status))))))

(defun serve (request)
  "Answer REQUEST, lisp's (COMMAND . ARGUMENTS), with the list (TEXT
EXIT-CODE).  Runs in a Slynk worker thread; an error is an answer too."
  (handler-case (multiple-value-bind (text code) (apply #'answer request)
                  (list text code))
    (error (condition)
      (list (format nil "lisp: ~a~%" condition) 1))))
