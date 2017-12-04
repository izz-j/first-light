(in-package :fl.core)

(defclass context ()
  ((%core-state :reader core-state
                :initarg :core-state)
   (%settings :reader settings
              :initform (make-hash-table))
   (%shaders :accessor shaders
             :initform nil)
   (%camera :accessor camera
            :initform nil)
   (%shared-storage-table :reader shared-storage-table
                          :initform (make-hash-table))))
