extends FlipperBase
class_name CloudFlipperBase

## Cloud Flipper Base
## Extends FlipperBase with one-way pass-through collision from below.
##
## All pass-through behavior is handled entirely in the Inspector — no extra
## code is required.  Godot 4 derives the one-way collision direction
## automatically from the shape's surface normal at the moment of contact,
## so a ball / turtle arriving from below (upward velocity) will pass through,
## while one arriving from above (falling down) will be blocked.
##
## REQUIRED INSPECTOR SETUP on the child CollisionShape2D:
##   ✅  One Way Collision  →  enabled
##   (One Way Collision Margin can stay at its default value)
##
## No overrides needed — the parent FlipperBase implementation is used as-is.
