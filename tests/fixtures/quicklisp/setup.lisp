;;;; Network-free Quicklisp facade used only to load-test the macOS driver.

(defpackage #:ql
  (:use #:cl)
  (:export #:quickload))

(in-package #:ql)

(defun quickload (systems &key silent)
  (declare (ignore silent))
  systems)

(in-package #:cl-user)
