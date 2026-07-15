# NotchLand Motion System

Motion in NotchLand communicates ownership, priority and continuity. A feature
must not invent its own spring for a normal interaction. It selects a semantic
role from `NotchMotionGraph`; repeating decoration uses `NotchAmbientMotion`.

## Measured interaction roles

| Role | Response | Damping | Delay | Purpose |
| --- | ---: | ---: | ---: | --- |
| Hover | 280 ms | 0.88 | 0 | Pointer acknowledgement |
| Zone reveal | 260 ms | 0.86 | 0 | Intent Hover destinations |
| Selection | 240 ms | 0.88 | 0 | Tabs, controls and choices |
| Content enter | 340 ms | 0.88 | 45 ms | Content inherits container motion |
| Container expand | 440 ms | 0.84 | 0 | Notch-to-panel shape change |
| Interruption | 360 ms | 0.90 | 0 | Calls, battery and priority events |
| Success | 420 ms | 0.70 | 0 | Payment, completion and unlock |
| Content return | 500 ms | 0.90 | 0 | Restore an interrupted surface |
| Dismiss | 220 ms | ease-in-out | 0 | Yield visual ownership quickly |

Reduced Motion replaces every interactive role with a 100 ms opacity-oriented
ease-out. Ambient loops are disabled where their movement is nonessential.

## Section choreography

1. The current surface compresses for 150 ms.
2. View identity changes after one display frame (16.7 ms at 60 Hz).
3. The container starts its 440 ms morph and remains the visual anchor.
4. New content enters 45 ms later from scale 0.78, offset -8 and blur 8.
5. Returning content uses a more damped 500 ms curve so interruption energy
   settles instead of producing a second bounce.

Only the root container owns width, height and corner-shape animation. Feature
views animate opacity, scale, blur and local controls. This prevents two springs
from fighting over layout and keeps the physical notch as the shared element.

## Ambient motion budget

Ambient movement never changes layout or gates an action. Pulse, orbit, shimmer,
celebration and spinner durations are centralized in `NotchAmbientMotion`.
Views must cancel tasks on disappearance and must not start decorative loops when
`accessibilityReduceMotion` is enabled.

## Adding a feature

- Use `.notchSection` for a normal section handoff and `.notchSuccess` for a
  completed action.
- Choose a semantic graph role for every `withAnimation` and `.animation` call.
- Do not embed a new response/damping pair in a feature view.
- Keep container geometry in the root presentation orchestrator.
- Add a measurement test if a new semantic role is genuinely necessary.
- Verify rapid switching, interruption and return, plus Reduced Motion.

The audit that introduced this system covered 180 animation, transition and
timeline call sites. Continuous media visualization timelines remain frame-driven;
they are render loops, not state-transition curves.
