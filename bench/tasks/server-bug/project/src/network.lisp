(in-package #:spool)

;;; Clients reach the server over TCP: a thread accepts connections, and
;;; each connection has a thread of its own that reads its requests, one
;;; per line, and writes the replies.

(defun open-listener (host port)
  (let ((socket (make-instance 'sb-bsd-sockets:inet-socket :type :stream :protocol :tcp)))
    (setf (sb-bsd-sockets:sockopt-reuse-address socket) t)
    (sb-bsd-sockets:socket-bind socket (sb-bsd-sockets:make-inet-address host) port)
    (sb-bsd-sockets:socket-listen socket 32)
    socket))

(defun start-listener (server host port)
  (let ((listener (open-listener host port)))
    (setf (server-listener server) listener
          (server-port server) (nth-value 1 (sb-bsd-sockets:socket-name listener))
          (server-listener-thread server)
          (sb-thread:make-thread (lambda () (accept-connections server))
                                 :name (format nil "spool listener ~D" (server-port server))))))

(defun accept-connections (server)
  (loop
    (let ((socket (handler-case (sb-bsd-sockets:socket-accept (server-listener server))
                    (sb-bsd-sockets:socket-error () nil))))
      (when (with-server-lock (server) (server-stopping server))
        (when socket
          (sb-bsd-sockets:socket-close socket))
        (return))
      (when socket
        (start-connection server socket)))))

(defun start-connection (server socket)
  (let ((stream (sb-bsd-sockets:socket-make-stream socket :input t :output t
                                                          :element-type 'character
                                                          :external-format :utf-8
                                                          :buffering :full)))
    (with-server-lock (server)
      (push socket (server-connections server)))
    (sb-thread:make-thread (lambda () (serve-connection server socket stream))
                           :name "spool connection")))

(defun serve-connection (server socket stream)
  "Answers the requests on STREAM until the client quits or goes away."
  (unwind-protect
       (handler-case
           (loop for line = (read-line stream nil)
                 while line
                 do (let ((reply (handle-request server (string-right-trim '(#\Return) line))))
                      (write-line reply stream)
                      (force-output stream)
                      (when (string= reply "OK bye")
                        (return))))
         ;; The client went away, or the server is stopping.
         (stream-error () nil))
    (with-server-lock (server)
      (setf (server-connections server) (remove socket (server-connections server))))
    (ignore-errors (close stream))))

(defun stop-listener (server)
  "Stops taking connections and ends the ones there are."
  (let ((listener (server-listener server)))
    (when listener
      ;; The listener thread waits in accept; a connection of our own
      ;; wakes it to see that the server is stopping.
      (ignore-errors
       (let ((socket (make-instance 'sb-bsd-sockets:inet-socket :type :stream :protocol :tcp)))
         (sb-bsd-sockets:socket-connect socket (sb-bsd-sockets:make-inet-address "127.0.0.1")
                                        (server-port server))
         (sb-bsd-sockets:socket-close socket)))
      (sb-thread:join-thread (server-listener-thread server) :default nil :timeout 10)
      (sb-bsd-sockets:socket-close listener)
      (dolist (socket (with-server-lock (server) (copy-list (server-connections server))))
        ;; Shutting the socket down wakes its thread from reading.
        (ignore-errors (sb-bsd-sockets:socket-shutdown socket :direction :io))))))
