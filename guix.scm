(add-to-load-path
 (string-append (dirname (canonicalize-path (current-filename)))
                "/modules"))

(use-modules (cl-art packages art))

cl-art
