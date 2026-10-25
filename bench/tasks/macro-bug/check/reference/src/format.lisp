(in-package #:stockfile)

;;; A record format says which columns a file has and how each becomes
;;; a slot of a structure. DEFINE-RECORD-FORMAT defines the structure and
;;; a parser for one line, and registers the format under its name for
;;; PARSE-RECORDS.

(defstruct (column (:constructor make-column (field header required)))
  "A column of a record format: the FIELD it fills, the HEADER it has in
a file's first line, and whether the file must have it."
  (field nil :type symbol :read-only t)
  (header "" :type string :read-only t)
  (required t :read-only t))

(defstruct (record-format
            (:constructor make-record-format (name columns delimiter parser)))
  "A format registered by DEFINE-RECORD-FORMAT. PARSER is called with a
simple vector of a line's cells, in the order of COLUMNS, and the line's
number, and returns the record."
  (name nil :type symbol :read-only t)
  (columns '() :type list :read-only t)
  (delimiter #\, :type character :read-only t)
  (parser nil :type function :read-only t))

(defvar *record-formats* (make-hash-table :test 'eq)
  "The record formats by name.")

(defun register-record-format (format)
  "Makes FORMAT the record format of its name, and returns it."
  (setf (gethash (record-format-name format) *record-formats*) format))

(defun find-record-format (name &optional (errorp t))
  "The record format NAME, or NIL when there is none and ERRORP is false."
  (or (gethash name *record-formats*)
      (when errorp
        (error "There is no record format ~S." name))))

(define-condition record-error (error)
  ((line :initarg :line :reader record-error-line)
   (field :initarg :field :reader record-error-field)
   (column :initarg :column :reader record-error-column)
   (text :initarg :text :initform nil :reader record-error-text)
   (message :initarg :message :reader record-error-message))
  (:report (lambda (condition stream)
             (format stream "Line ~D, column ~S: ~A"
                     (record-error-line condition)
                     (record-error-column condition)
                     (record-error-message condition))))
  (:documentation "A line of a file that does not make a record: its
LINE number, counted from 1 for the header line, the FIELD and the
COLUMN header it is about, the cell's TEXT, and a MESSAGE."))

(defun signal-record-error (line field column text control &rest arguments)
  "Signals a RECORD-ERROR, its message made by FORMAT from CONTROL and
ARGUMENTS."
  (error 'record-error :line line :field field :column column :text text
                       :message (apply #'format nil control arguments)))

(defun read-cell (type text line field column)
  "The value of type TYPE in the cell TEXT, which is not blank, for FIELD
of the record on LINE; a cell that is not one signals a RECORD-ERROR."
  (handler-case (convert-cell type text)
    (invalid-cell (condition)
      (signal-record-error line field column text "~A" condition))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun parse-field-spec (spec)
    "The field SPEC of DEFINE-RECORD-FORMAT, (NAME HEADER &key TYPE
DEFAULT CHECK), as a property list, with :DEFAULTP true when it has a
default."
    (destructuring-bind (name header &key (type :string) (default nil defaultp)
                                          check)
        spec
      (check-type name (and symbol (not null)))
      (check-type header string)
      (list :name name :header header :type type
            :default default :defaultp defaultp :check check)))

  (defun field-binding-form (field index cells line body)
    "A form that binds FIELD's variable to the value of the cell at INDEX
of the vector that the variable CELLS holds, tests FIELD's check and
then evaluates BODY in that binding. LINE is the variable that holds the
line's number. A blank cell takes the field's default, or is an error
for a field without one.

The field's own forms, its default and check, see only the fields'
variables: CELLS and LINE are the macro's gensyms, and so is the
variable for the cell's text."
    (destructuring-bind (&key name header type default defaultp check) field
      (alexandria:with-gensyms (text)
        `(let ((,name (let ((,text (svref ,cells ,index)))
                        (if (blank-cell-p ,text)
                            ,(if defaultp
                                 default
                                 `(signal-record-error ,line ',name ,header ,text
                                                       "the cell is empty"))
                            (read-cell ',type ,text ,line ',name ,header)))))
           ,@(when check
               `((unless ,check
                   (signal-record-error ,line ',name ,header (svref ,cells ,index)
                                        "~S does not hold" ',check))))
           ,body)))))

(defmacro define-record-format (name (&key (delimiter #\,)) &body fields)
  "Defines the record format NAME: a structure NAME with a slot for each
field, made by MAKE-NAME with a keyword argument for each, and a parser
that PARSE-RECORDS uses to make one from each line of a file.

DELIMITER separates the cells of a line. FIELDS may start with a
docstring for the structure. Each field is

  (FIELD-NAME HEADER &key TYPE DEFAULT CHECK)

HEADER is the heading of the field's column in the file's first line.
TYPE is a cell type that CONVERT-CELL knows, :STRING by default. DEFAULT
is a form evaluated when the cell is blank; a field without a default
must have a value, and its column must be in the file. CHECK is a form
that must be true of the value; it and DEFAULT are evaluated with the
fields before this one bound to their values, as a LET* would.

The fields are read in order, so a later field's DEFAULT or CHECK may
use the fields before it."
  (let* ((documentation (when (and (stringp (first fields)) (rest fields))
                          (first fields)))
         (fields (mapcar #'parse-field-spec
                         (if documentation (rest fields) fields)))
         (names (mapcar (lambda (field) (getf field :name)) fields))
         (constructor (alexandria:symbolicate '#:make- name)))
    (alexandria:with-gensyms (format cells line)
      `(progn
         (defstruct (,name (:constructor ,constructor (&key ,@names)))
           ,@(when documentation (list documentation))
           ,@names)
         (let ((,format
                 (make-record-format
                  ',name
                  (list ,@(mapcar (lambda (field)
                                    `(make-column ',(getf field :name)
                                                  ,(getf field :header)
                                                  ,(not (getf field :defaultp))))
                                  fields))
                  ,delimiter
                  (lambda (,cells ,line)
                    (declare (type simple-vector ,cells))
                    ,(reduce (lambda (field-and-index body)
                               (destructuring-bind (field . index) field-and-index
                                 (field-binding-form field index cells line body)))
                             (loop for field in fields
                                   for index from 0
                                   collect (cons field index))
                             :from-end t
                             :initial-value
                             `(,constructor
                               ,@(loop for name in names
                                       append (list (alexandria:make-keyword name)
                                                    name))))))))
           (register-record-format ,format)
           ',name)))))
