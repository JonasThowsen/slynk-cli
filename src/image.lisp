;;;; src/image.lisp -- what the image lisp start starts loads first
;;;; (README.md, "The project").  lisp start passes what it needs in the
;;;; environment: SLYNK_CLI_ROOT, SLYNK_CLI_STATE, SLYNK_CLI_PORT,
;;;; SLYNK_CLI_SYSTEM, SLYNK_CLI_INIT and SLYNK_CLI_MAIN; the server reads
;;;; SLYNK_CLI_DISPATCHER.  Each step reports on standard
;;;; output, which goes to image.log, in lines that start with "slynk-cli: ";
;;;; lisp start reads them there.

(require "asdf")
(require "sb-posix")

(defpackage #:slynk-cli-image
  (:use #:cl))
(in-package #:slynk-cli-image)

(defun say (format-control &rest arguments)
  (format t "~&slynk-cli: ~?~%" format-control arguments)
  (finish-output))

(defun environment (name)
  "The value of the environment variable NAME, or NIL when it is unset or empty."
  (let ((value (sb-ext:posix-getenv name)))
    (and value (plusp (length value)) value)))

(defun environment-directory (name)
  (let ((value (environment name)))
    (and value (pathname (concatenate 'string (string-right-trim "/" value) "/")))))

(defparameter *root* (environment-directory "SLYNK_CLI_ROOT"))
(defparameter *state* (environment-directory "SLYNK_CLI_STATE"))

;;; The root's systems: every directory under the root that holds an .asd
;;; file, except directories whose name starts with a dot and directories
;;; reached through a symbolic link.  They are found first, before every
;;; other source of systems, so the root's copy of a system wins.

(defun symbolic-link-p (directory)
  (sb-posix:s-islnk
   (sb-posix:stat-mode (sb-posix:lstat (string-right-trim "/" (namestring directory))))))

(defun subdirectories (directory)
  (remove-if (lambda (subdirectory)
               (let ((name (car (last (pathname-directory subdirectory)))))
                 (or (not (stringp name))
                     (char= (char name 0) #\.)
                     (symbolic-link-p subdirectory))))
             (directory (merge-pathnames (make-pathname :directory '(:relative :wild)) directory)
                        :resolve-symlinks nil)))

(defun root-systems (root)
  "A table from each system name under ROOT to its .asd file.  Of two
files of the same name, the one nearer the root wins."
  (let ((systems (make-hash-table :test 'equal)))
    (loop for directories = (list root)
            then (mapcan #'subdirectories directories)
          while directories
          do (dolist (directory directories)
               (dolist (file (directory (merge-pathnames "*.asd" directory)
                                        :resolve-symlinks nil))
                 (let ((name (string-downcase (pathname-name file))))
                   (unless (gethash name systems)
                     (setf (gethash name systems) file))))))
    systems))

(defvar *root-systems* (make-hash-table :test 'equal))

(defun search-root (name)
  "ASDF's search function for the root's systems."
  (values (gethash (asdf:primary-system-name name) *root-systems*)))

(defun register-root ()
  (setf *root-systems* (root-systems *root*))
  (setf asdf:*system-definition-search-functions*
        (cons 'search-root (remove 'search-root asdf:*system-definition-search-functions*))))

;;; Slynk: where SLYNK_CLI_SLYNK says, else where ASDF finds it, else in a
;;; SLY that Emacs installed.

(defun emacs-slynk ()
  (first (loop for pattern in '("~/.emacs.d/elpa/sly-*/slynk/slynk.asd"
                                "~/.config/emacs/elpa/sly-*/slynk/slynk.asd"
                                "~/.emacs.d/straight/repos/sly/slynk/slynk.asd"
                                "~/.config/emacs/straight/repos/sly/slynk/slynk.asd")
               append (ignore-errors
                       (sort (directory (merge-pathnames (subseq pattern 2)
                                                         (user-homedir-pathname)))
                             #'string> :key #'namestring)))))

(defun load-slynk ()
  (let ((asd (let ((directory (environment-directory "SLYNK_CLI_SLYNK")))
               (cond (directory (merge-pathnames "slynk.asd" directory))
                     ((asdf:find-system "slynk" nil) nil)
                     (t (or (emacs-slynk)
                            (progn
                              (say "no Slynk found. Install SLY in Emacs, load it with ~
                                    (ql:quickload :slynk), or set SLYNK_CLI_SLYNK to a ~
                                    directory with slynk.asd.")
                              (sb-ext:exit :code 1 :abort t))))))))
    (when asd
      (asdf:load-asd asd))
    (let ((*compile-verbose* nil) (*compile-print* nil) (*load-verbose* nil))
      (handler-bind ((warning #'muffle-warning))
        (asdf:load-system "slynk")))))

(defun load-server ()
  (let* ((source (merge-pathnames "server.lisp" *load-truename*))
         (fasl (merge-pathnames "fasl/slynk-cli/server.fasl" *state*)))
    (load (compile-file source :output-file (ensure-directories-exist fasl)
                               :verbose nil :print nil))))

(defun load-project-system (name)
  "Load the system NAME, through Quicklisp when it is loaded."
  (if (find-package "QL")
      (uiop:symbol-call "QL" "QUICKLOAD" name)
      (asdf:load-system name)))

(defun start ()
  (dolist (file (uiop:split-string (or (environment "SLYNK_CLI_INIT") "")
                                   :separator '(#\Newline)))
    (when (plusp (length file))
      (load file)))
  (register-root)
  (asdf:initialize-output-translations
   `(:output-translations
     (,(namestring *root*) ,(namestring (merge-pathnames "fasl/" *state*)))
     :inherit-configuration))
  (load-slynk)
  ;; Slynk would put its own debugger in every thread when a connection
  ;; opens, one that waits for an editor; lisp's pauses them instead.
  (setf (symbol-value (find-symbol "*GLOBAL-DEBUGGER*" "SLYNK")) nil)
  (load-server)
  ;; SLY's compile-file writes the compiled file beside the source; put it
  ;; with the image's other compiled files.
  (setf (symbol-value (find-symbol "*FASL-PATHNAME-FUNCTION*" "SLYNK"))
        (lambda (source options)
          (declare (ignore options))
          (ensure-directories-exist (asdf:compile-file-pathname* source))))
  (let ((port (uiop:symbol-call "SLYNK" "CREATE-SERVER"
                                :port (parse-integer (or (environment "SLYNK_CLI_PORT") "0"))
                                :interface "127.0.0.1" :dont-close t)))
    (say "port ~d" port))
  (let ((system (environment "SLYNK_CLI_SYSTEM")))
    (if system
        (handler-case (progn (load-project-system system)
                             (say "~a loaded" system))
          (error (condition)
            (say "loading ~a failed:~%~a" system condition)))
        (say "no system loaded")))
  (say "ready"))

(defun main-function (name)
  "The function NAME names, such as \"my-app::main\", read without evaluation."
  (let ((symbol (ignore-errors (with-standard-io-syntax
                                 (let ((*read-eval* nil)) (read-from-string name))))))
    (unless (and symbol (symbolp symbol) (fboundp symbol))
      (error "the :main function ~a is not defined" name))
    symbol))

(defun run-main-thread ()
  "What the main thread does once the image is ready: the project's :main
function, then the queue of forms for lisp eval --main, until the image is
stopped.  An error in it, as in any thread lisp did not start, pauses it as
an evaluation of its own."
  (let ((hook (find-symbol "FOREIGN-PAUSE" "SLYNK-CLI"))
        (main (environment "SLYNK_CLI_MAIN")))
    (setf sb-ext:*invoke-debugger-hook* hook
          (symbol-value (find-symbol "*OUTER-RESTARTS*" "SLYNK-CLI")) (compute-restarts))
    (let ((sb-ext:*invoke-debugger-hook* hook)
          (*debugger-hook* nil))
      (when main
        ;; No handler around the function itself: its errors pause.
        (let ((function (handler-case (main-function main)
                          (error (condition)
                            (say "~a" condition)
                            nil))))
          (when function
            (say "running ~a in the main thread" main)
            (funcall function)
            (say "~a returned" main))))
      ;; Standard input is empty; the main thread serves lisp eval --main
      ;; until the image is stopped.
      (uiop:symbol-call "SLYNK-CLI" "SERVE-MAIN-THREAD"))))

(handler-case (start)
  (error (condition)
    (say "the image could not start: ~a" condition)
    (sb-ext:exit :code 1 :abort t)))
;; Outside the handler above, so an error in the main thread pauses.
(run-main-thread)
