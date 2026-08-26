(define-module (tests package)
  #:use-module (cl-art packages art)
  #:use-module (cl-art packages lisp)
  #:use-module (guix packages)
  #:use-module (srfi srfi-1))

(define (input-package input)
  (and (pair? input)
       (pair? (cdr input))
       (package? (cadr input))
       (cadr input)))

(define propagated-packages
  (filter-map input-package (package-propagated-inputs cl-art)))

(define propagated-names
  (map package-name propagated-packages))

(define closure-names
  (map package-name %cl-art-lisp-packages))

(define (closure-package name)
  (find (lambda (package)
          (string=? name (package-name package)))
        %cl-art-lisp-packages))

(define (native-input-names package)
  (filter-map (lambda (input)
                (let ((package (input-package input)))
                  (and package (package-name package))))
              (package-native-inputs package)))

(define expected-lisp-packages
  '("sbcl-alexandria"
    "sbcl-babel"
    "sbcl-bordeaux-threads"
    "sbcl-cffi"
    "sbcl-chipz"
    "sbcl-chunga"
    "sbcl-cl+ssl"
    "sbcl-cl-autowrap"
    "sbcl-cl-base64"
    "sbcl-cl-cookie"
    "sbcl-cl-fad"
    "sbcl-cl-json"
    "sbcl-cl-opengl"
    "sbcl-cl-ppcre"
    "sbcl-cl-utilities"
    "sbcl-closer-mop"
    "sbcl-defpackage-plus"
    "sbcl-dexador"
    "sbcl-documentation-utils"
    "sbcl-fast-http"
    "sbcl-fast-io"
    "sbcl-flexi-streams"
    "sbcl-float-features"
    "sbcl-global-vars"
    "sbcl-local-time"
    "sbcl-proc-parse"
    "sbcl-quri"
    "sbcl-sdl2"
    "sbcl-sdl2-image"
    "sbcl-sdl2-ttf"
    "sbcl-shasht"
    "sbcl-smart-buffer"
    "sbcl-split-sequence"
    "sbcl-static-vectors"
    "sbcl-trivial-channels"
    "sbcl-trivial-do"
    "sbcl-trivial-features"
    "sbcl-trivial-garbage"
    "sbcl-trivial-gray-streams"
    "sbcl-trivial-indent"
    "sbcl-trivial-mimes"
    "sbcl-trivial-timeout"
    "sbcl-usocket"
    "sbcl-xsubseq"))

(unless (string=? "cl-art" (package-name cl-art))
  (error "unexpected package name" (package-name cl-art)))

(let ((missing (lset-difference string=? closure-names propagated-names)))
  (unless (null? missing)
    (error "cl-art does not propagate its complete Lisp closure" missing)))

(let ((missing (lset-difference string=? expected-lisp-packages closure-names)))
  (unless (null? missing)
    (error "missing direct ART Lisp dependencies" missing)))

(for-each
 (lambda (name)
   (let ((package (closure-package name)))
     (unless package
       (error "the ART closure does not contain a repaired package" name))
     (unless (member "c2ffi" (native-input-names package))
       (error "the ART package does not carry its c2ffi repair" name))))
 '("sbcl-cl-autowrap" "sbcl-sdl2-image" "sbcl-sdl2-ttf"))

(for-each
 (lambda (name)
   (let ((package (closure-package name)))
     (unless (member "sdl2" (native-input-names package))
       (error "the ART SDL wrapper lacks its header input" name))))
 '("sbcl-sdl2-image" "sbcl-sdl2-ttf"))

(display "cl-art package boundary checks passed\n")
