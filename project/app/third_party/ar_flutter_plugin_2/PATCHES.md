# Local patches to ar_flutter_plugin_2 0.0.3

Vendored from pub.dev (MIT, see LICENSE) because upstream drag/twist was
broken on the vivo test phone. Every change is marked `PATCH(structural-vision)`
in `android/src/main/kotlin/com/uhg0/ar_flutter_plugin_2/ArView.kt`.

1. **Drag and twist, scene-wide.** Upstream `onMoveBegin` discarded its own
   result, SceneView's node drag moved models the wrong way, and twist never
   fired. Node-level editing is off; `setOnGestureListener` now drags the model
   under the finger (else the only model) along the tracked plane under the
   finger, from the grab point, and twists it about the vertical anywhere on
   screen. The final local position + yaw goes back to Dart as `onPanEnd` /
   `onRotationEnd`. Yaw is accumulated per node, never read back from
   `Node.rotation`: that comes from `Quaternion.toEulerAngles()`, whose yaw is an
   asin capped at +-90 degrees, which pinned a twist at 90.
2. **`transformationChanged` keeps the node's scale.** SceneView's
   `scaleToUnits` works by setting the node's scale, so applying the Dart
   matrix's scale made a moved model jump in size. Position and yaw only
   (radians in the matrix, degrees in SceneView).

Still broken upstream, not used by the app: `getCameraPose` (returns a map the
Dart side reads as a list, and calls `session.update()` off the render loop)
and `getPose(anchor)` (only finds cloud anchors).
