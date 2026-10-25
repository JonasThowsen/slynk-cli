(in-package #:tally)

(defclass sales-database ()
  ((sales :initform (make-hash-table)
          :reader database-sales
          :documentation "Every sale, by its id.")
   (stores :initform (make-hash-table :test 'equal)
           :reader database-store-days
           :documentation "For each store id, a hash table from day number
to the list of that day's sales, the most recently added first.")
   (strings :initform (make-hash-table :test 'equal)
            :reader database-strings
            :documentation "One copy of each store id and SKU seen, so that
the sales of a store or product share their strings.")
   (first-day :initform nil
              :accessor database-first-day
              :documentation "The earliest day with a sale, or NIL.")
   (last-day :initform nil
             :accessor database-last-day
             :documentation "The latest day with a sale, or NIL."))
  (:documentation "The sales of a chain of stores, indexed by store and day."))

(defun make-sales-database ()
  "Returns an empty sales database."
  (make-instance 'sales-database))

(defun shared-string (database string)
  "Returns DATABASE's copy of STRING, making STRING the copy if it has none."
  (alexandria:ensure-gethash string (database-strings database)
                             (coerce string 'simple-string)))

(defun store-days (database store &key create)
  "Returns the table from day to sales of STORE in DATABASE. Without
CREATE, a store with no sales gives NIL."
  (let ((stores (database-store-days database)))
    (or (gethash store stores)
        (and create
             (setf (gethash (shared-string database store) stores)
                   (make-hash-table))))))

(defun database-stores (database)
  "Returns the ids of the stores in DATABASE, sorted."
  (sort (alexandria:hash-table-keys (database-store-days database)) #'string<))

(defun database-sale-count (database)
  "Returns the number of sales in DATABASE."
  (hash-table-count (database-sales database)))

(defun find-sale (database id)
  "Returns the sale with ID in DATABASE, or NIL."
  (values (gethash id (database-sales database))))

(defun add-sale (database sale)
  "Adds SALE to DATABASE and returns it. A sale whose id is already there
is an error."
  (let ((id (sale-id sale))
        (day (sale-day sale)))
    (when (find-sale database id)
      (error "Sale ~D is already in the database." id))
    (setf (gethash id (database-sales database)) sale)
    (push sale (gethash day (store-days database (sale-store sale) :create t)))
    (when (or (null (database-first-day database))
              (< day (database-first-day database)))
      (setf (database-first-day database) day))
    (when (or (null (database-last-day database))
              (> day (database-last-day database)))
      (setf (database-last-day database) day))
    sale))

(defun void-sale (database id)
  "Removes the sale with ID from DATABASE, as when a till voids a receipt,
and returns it. Voiding a sale that is not there is an error."
  (let ((sale (or (find-sale database id)
                  (error "There is no sale ~D." id))))
    (remhash id (database-sales database))
    (let ((days (store-days database (sale-store sale))))
      (setf (gethash (sale-day sale) days)
            (remove sale (gethash (sale-day sale) days))))
    sale))

(defun import-sales (database stream)
  "Reads sales from STREAM, one per line as PARSE-SALE-LINE reads them,
into DATABASE. A first line that starts with \"id,\" is a header and is
skipped. Returns the number of sales read."
  (flet ((share (string) (shared-string database string)))
    (loop for line = (read-line stream nil)
          for first = t then nil
          while line
          unless (or (zerop (length line))
                     (and first (eql 0 (search "id," line))))
            do (add-sale database (parse-sale-line line :intern-string #'share))
            and count t)))
