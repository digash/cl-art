;; This authenticated fork revision is a root snapshot.  Bootstrap it with
;; `guix pull -p' as documented; `guix time-machine' requires older ancestry.
(list
 (channel
  (name 'guix)
  (url "https://gitlab.com/digash/guix-channel.git")
  (branch "signed/channel-snapshot")
  (commit "a17ba2029ee1b54684589bfd892b498e1f459d47")
  (introduction
   (make-channel-introduction
    "a17ba2029ee1b54684589bfd892b498e1f459d47"
    (openpgp-fingerprint
     "4702 823D EED3 1B08 DBB4  9DBC 6BC7 A41A 169B 48DB")))))
