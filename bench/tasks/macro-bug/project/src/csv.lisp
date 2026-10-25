(in-package #:stockfile)

;;; The files are what spreadsheets and the scanners' software write:
;;; one record per line, cells separated by a delimiter, and a cell in
;;; double quotes when it holds the delimiter itself.

(defun split-csv-line (line &key (delimiter #\,))
  "Splits LINE into a list of cell strings at DELIMITER.
A cell may be quoted with double quotes; inside them the delimiter is
ordinary text and two double quotes stand for one."
  (let ((cells '())
        (cell (make-string-output-stream))
        (quoted nil)
        (i 0)
        (end (length line)))
    (loop while (< i end)
          do (let ((char (char line i)))
               (cond (quoted
                      (cond ((char/= char #\")
                             (write-char char cell))
                            ((and (< (1+ i) end)
                                  (char= (char line (1+ i)) #\"))
                             (write-char #\" cell)
                             (incf i))
                            (t
                             (setf quoted nil))))
                     ((char= char #\")
                      (setf quoted t))
                     ((char= char delimiter)
                      (push (get-output-stream-string cell) cells))
                     (t
                      (write-char char cell))))
             (incf i))
    (push (get-output-stream-string cell) cells)
    (nreverse cells)))

(defun strip-line-ending (line)
  "LINE without the carriage return that files written on Windows end
their lines with."
  (let ((end (length line)))
    (if (and (plusp end) (char= (char line (1- end)) #\Return))
        (subseq line 0 (1- end))
        line)))

(defun blank-line-p (line)
  "True when LINE has nothing but spaces and tabs."
  (every (lambda (char) (member char '(#\Space #\Tab))) line))
