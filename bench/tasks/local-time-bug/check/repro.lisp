;;;; The reported case: 29 February of a year divisible by 400 decodes
;;;; as 1 March. Also checks its neighbours and that every day from 1600
;;;; to 2800 survives a decode and encode round trip.

(in-package :cl-user)

(defun reproduction-failures ()
  (let ((failures '())
        (utc local-time:+utc-zone+))
    (flet ((expect-date (string)
             (let* ((timestamp (local-time:parse-timestring string))
                    (formatted (local-time:format-timestring
                                nil timestamp
                                :format local-time:+iso-8601-date-format+
                                :timezone utc)))
               (unless (string= formatted string)
                 (push (format nil "~A formats as ~A" string formatted) failures)))))
      (dolist (date '("2000-02-29" "2000-03-01" "2000-02-28" "2400-02-29"
                      "1600-02-29" "2024-02-29" "1900-02-28" "1900-03-01"))
        (expect-date date)))
    (let ((leap-day (local-time:parse-timestring "2000-02-29")))
      (unless (and (= 29 (local-time:timestamp-day leap-day :timezone utc))
                   (= 2 (local-time:timestamp-month leap-day :timezone utc)))
        (push "timestamp-day/-month of 2000-02-29 are not 29 and 2" failures)))
    (let ((next (local-time:timestamp+ (local-time:parse-timestring "2000-02-28")
                                       1 :day utc)))
      (unless (= 29 (local-time:timestamp-day next :timezone utc))
        (push "2000-02-28 plus one day is not the 29th" failures)))
    (loop with timestamp = (local-time:make-timestamp)
          for day from (- (* 400 365)) to (* 800 365)
          do (setf (local-time:day-of timestamp) day)
             (multiple-value-bind (nsec sec minute hour day-of-month month year)
                 (local-time:decode-timestamp timestamp :timezone utc)
               (let ((again (local-time:encode-timestamp nsec sec minute hour
                                                         day-of-month month year
                                                         :timezone utc)))
                 (unless (= day (local-time:day-of again))
                   (push (format nil "day ~D decodes as ~D-~2,'0D-~2,'0D, which encodes as day ~D"
                                 day year month day-of-month (local-time:day-of again))
                         failures)
                   (loop-finish)))))
    (nreverse failures)))
