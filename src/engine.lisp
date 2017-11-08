(in-package :gear)

(defmacro prepare-engine (core-state path)
  `(progn
     ,@(loop :with items = '(context call-flow scene)
             :for item :in items
             :for var = (symbolicate '%temp- item)
             :collect `(let ((,var (make-hash-table :test #'eq)))
                         (declare (special ,var))
                         (flet ((%prepare ()
                                  (load-extensions ',item ,path)
                                  ,var))
                           (maphash
                            (lambda (k v)
                              (setf (gethash k (,(symbolicate item '-table)
                                                ,core-state))
                                    v))
                            (%prepare)))))
     (setf (shaders ,core-state)
           (make-instance 'shaders
                          :data (make-shader-dictionary ,path)))))

(defmethod start-engine ()
  (let* ((user-package-name (package-name *package*))
         (path (get-path user-package-name "data"))
         (core-state (make-instance 'core-state)))
    (kit.sdl2:init)
    (sdl2:in-main-thread ()
      (let ((*package* (find-package :gear)))
        (prepare-engine core-state path)
        (load-default-scene core-state)
        (make-display core-state)
        (compile-shaders core-state)))
    (kit.sdl2:start)
    core-state))

#+sbcl
(defmacro profile (seconds)
  `(progn
     (let ((display (display (start-engine))))
       (sb-profile:unprofile)
       (sb-profile:profile
        "GEAR"
        "GEAR-EXAMPLE"
        "GAMEBOX-MATH"
        "GAMEBOX-FRAME-MANAGER")
       (sleep ,seconds)
       (sb-profile:report)
       (sb-profile:unprofile)
       (sb-profile:reset)
       (quit-engine display))))
