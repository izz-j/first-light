(in-package :gear)

(%define-core-component transform ()
  (parent nil)
  (children nil)
  (translation (%make-transform-state 'transform-state-vector))
  (rotation (%make-transform-state 'transform-state-quaternion
                                   :incremental (vec)))
  (scale (%make-transform-state 'transform-state-vector
                                :current (vec 1 1 1)))
  (local (mid))
  (model (mid)))

(defun add-child (parent child)
  (push child (children parent))
  (setf (parent child) parent))

(defun translate-node (node)
  (with-slots (%current %incremental %previous) (translation node)
    (vcp! %previous %current)
    (v+! %current %current %incremental)))

(defun rotate-node (node)
  (with-slots (%current %incremental %previous) (rotation node)
    (qcp! %previous %current)
    (qrot! %current %current %incremental)))

(defun scale-node (node)
  (with-slots (%current %incremental %previous) (scale node)
    (vcp! %previous %current)
    (v+! %current %current %incremental)))

(defun transform-node (node)
  (scale-node node)
  (rotate-node node)
  (translate-node node))

(defun resolve-local (node alpha)
  (with-slots (%scale %rotation %translation %local) node
    (interpolate-state %scale alpha)
    (interpolate-state %rotation alpha)
    (interpolate-state %translation alpha)
    (m*! %local
         (q->m! %local (interpolated %rotation))
         (v->mscale +mid+ (interpolated %scale)))
    (v->mtr! %local (interpolated %translation))))

(defun resolve-model (node alpha)
  (with-slots (%parent %local %model) node
    (when %parent
      (resolve-local node alpha)
      (m*! %model (model %parent) %local)
      %model)))

(defun map-nodes (func parent)
  (funcall func parent)
  (dolist (child (children parent))
    (map-nodes func child)))

(defun interpolate-transforms (root-node alpha)
  (map-nodes
   (lambda (node)
     (resolve-model node alpha))
   root-node))

(defmethod reinitialize-instance ((instance transform)
                                  &key
                                    actor
                                    (translation/current (vec) tc-p)
                                    (translation/incremental (vec) ti-p)
                                    (rotation/current (vec) rc-p)
                                    (rotation/incremental (vec) ri-p)
                                    (scale/current (vec 1 1 1) sc-p)
                                    (scale/incremental (vec) si-p))
  (with-slots (%actor %state %translation %rotation %scale) instance
    (setf %actor actor
          %state :initialize)
    (when tc-p (setf (current %translation) translation/current))
    (when ti-p (setf (incremental %translation) translation/incremental))
    (when rc-p (setf (current %rotation) (qrot +qid+ rotation/current)))
    (when ri-p (setf (incremental %rotation) rotation/incremental))
    (when sc-p (setf (current %scale) scale/current))
    (when si-p (setf (incremental %scale) scale/incremental))))
