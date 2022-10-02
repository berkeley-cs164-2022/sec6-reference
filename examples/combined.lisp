(let ((r (ref 1)))
  (do (set-ref r 2)
      (deref r)))