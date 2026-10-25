(in-package #:stockfile)

;;; Reading a file: the first line that is not blank names the columns,
;;; in any order; each line after it that is not blank is a record.
;;; Lines are numbered as an editor numbers them, blank ones included, so
;;; that an error points at the line a person sees.

(defun header-positions (header-cells format line)
  "For each column of FORMAT, the position of its header among
HEADER-CELLS, compared without case, or NIL for an optional column the
file does not have. A required column that is missing signals a
RECORD-ERROR for the header LINE."
  (loop for column in (record-format-columns format)
        for position = (position (column-header column) header-cells
                                 :test #'string-equal :key #'trim-cell)
        when (and (null position) (column-required column))
          do (signal-record-error line (column-field column)
                                  (column-header column) nil
                                  "the file has no such column")
        collect position))

(defun select-cells (cells positions)
  "A simple vector of the elements of the list CELLS at POSITIONS, in
that order, with an empty cell for a NIL position or for a position past
the end of a short line."
  (map 'simple-vector
       (lambda (position)
         (or (and position (nth position cells)) ""))
       positions))

(defun parse-records (stream format-name &key (on-error :signal))
  "Reads the records of the record format FORMAT-NAME from STREAM and
returns them in order, and as a second value the list of RECORD-ERRORs
for lines that did not make one.

ON-ERROR says what a line that does not make a record does. :SIGNAL, the
default, signals its RECORD-ERROR, with a CONTINUE restart that skips the
line; :COLLECT skips the line and adds the error to the second value. A
file without one of the format's required columns is an error either
way."
  (check-type on-error (member :signal :collect))
  (let* ((format (find-record-format format-name))
         (delimiter (record-format-delimiter format))
         (parser (record-format-parser format))
         (positions nil)
         (header-read nil)
         (records '())
         (errors '()))
    (flet ((parse-line (cells line-number)
             (restart-case
                 (push (funcall parser (select-cells cells positions) line-number)
                       records)
               (continue ()
                 :report "Skip this line."
                 nil))))
      (loop for line-number from 1
            for line = (read-line stream nil)
            while line
            do (let ((line (strip-line-ending line)))
                 (cond ((blank-line-p line))
                       ((not header-read)
                        (setf positions (header-positions
                                         (split-csv-line line :delimiter delimiter)
                                         format line-number)
                              header-read t))
                       (t
                        (let ((cells (split-csv-line line :delimiter delimiter)))
                          (if (eq on-error :collect)
                              (handler-case (parse-line cells line-number)
                                (record-error (condition)
                                  (push condition errors)))
                              (parse-line cells line-number))))))))
    (values (nreverse records) (nreverse errors))))

(defun import-file (pathname format-name &key (on-error :signal))
  "PARSE-RECORDS of the file PATHNAME, read as UTF-8."
  (with-open-file (stream pathname :external-format :utf-8)
    (parse-records stream format-name :on-error on-error)))
