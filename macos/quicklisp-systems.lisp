;;;; Load or verify cl-art's Quicklisp systems without changing the dist.

(require :asdf)

(defparameter *cl-art-quicklisp-setup*
  (or (sb-ext:posix-getenv "CL_ART_QUICKLISP_SETUP")
      (error "CL_ART_QUICKLISP_SETUP is not set")))

(unless (probe-file *cl-art-quicklisp-setup*)
  (error "Quicklisp setup does not exist: ~a" *cl-art-quicklisp-setup*))

(load *cl-art-quicklisp-setup*)

#+(and darwin arm64)
(defun ensure-cl-art-arch-specs ()
  "Supply the Darwin ARM64 autowrap specs shipped only under the x86_64 name."
  (dolist (src (directory (merge-pathnames
                           "dists/**/src/spec/*.x86_64-apple-darwin9.spec"
                           (truename
                            (merge-pathnames
                             "./"
                             (make-pathname :name nil
                                            :type nil
                                            :defaults
                                            *cl-art-quicklisp-setup*))))))
    (let ((dst (make-pathname
                :name (let ((name (pathname-name src)))
                        (concatenate 'string
                                     (subseq name 0 (search "x86_64" name))
                                     "aarch64"
                                     (subseq name
                                             (+ (search "x86_64" name) 6))))
                :defaults src)))
      (unless (probe-file dst)
        (uiop:copy-file src dst)))))

(defparameter *cl-art-systems*
  '(:dexador :shasht :quri :sdl2 :sdl2-image :sdl2-ttf))

(defun muffle-known-quicklisp-redefinition (condition)
  "Muffle only the two benign redefinitions emitted by this Quicklisp graph."
  (let ((message (princ-to-string condition)))
    (when (or (search "DEFPACKAGE-PLUS-1::DEFPACKAGE+-DISPATCH" message)
              (search "SDL2-FFI.FUNCTIONS:POSIX-MEMALIGN" message))
      (muffle-warning condition))))

(let ((mode (or (sb-ext:posix-getenv "CL_ART_QUICKLISP_MODE") "check")))
  (cond
    ((string= mode "preload")
     #+(and darwin arm64) (ensure-cl-art-arch-specs)
     (funcall (or (find-symbol "QUICKLOAD" :ql)
                  (error "Quicklisp did not define QL:QUICKLOAD"))
              *cl-art-systems*
              :silent t))
    ((string= mode "check")
     ;; Verify Quicklisp's installed-release metadata before asking ASDF to
     ;; load anything.  Neither operation can fetch a missing release, unlike
     ;; QL:QUICKLOAD, so --check remains network-free.
     (let* ((ql-dist (or (find-package "QL-DIST")
                         (error "Quicklisp did not define QL-DIST")))
            (find-system
             (symbol-function (or (find-symbol "FIND-SYSTEM" ql-dist)
                                  (error "QL-DIST:FIND-SYSTEM is absent"))))
            (installedp
             (symbol-function (or (find-symbol "INSTALLEDP" ql-dist)
                                  (error "QL-DIST:INSTALLEDP is absent")))))
       (dolist (system *cl-art-systems*)
         (let ((quicklisp-system
                (funcall find-system
                         (string-downcase (symbol-name system)))))
           (unless (and quicklisp-system
                        (funcall installedp quicklisp-system))
             (error "Quicklisp system is not installed: ~a" system)))
         (unless (asdf:find-system system nil)
           (error "ASDF cannot find installed Quicklisp system: ~a" system))
         ;; These releases intentionally redefine one generic dispatcher and
         ;; one generated FFI function.  Suppress those exact warnings while
         ;; keeping every other load or compilation warning visible.
         (handler-bind ((warning #'muffle-known-quicklisp-redefinition))
           (asdf:load-system system)))))
    (t
     (error "unknown CL_ART_QUICKLISP_MODE: ~a" mode))))

(format t "~&cl-art Quicklisp systems ~a successfully~%"
        (if (string= (sb-ext:posix-getenv "CL_ART_QUICKLISP_MODE") "preload")
            "preloaded"
            "verified"))
