# Face Unlock Beta — Security Boundary

NotchLand Face Unlock is convenience-grade protection for private application
modules. It is not Apple Face ID, a macOS credential, or a replacement for
LocalAuthentication.

## Data flow

1. Enrollment begins only after successful system authentication.
2. `AVCaptureSession` provides temporary in-memory frames.
3. Vision detects one face, checks capture quality, estimates yaw and crops the face.
4. Vision converts the crop into a mathematical feature print.
5. Three centered templates and a per-profile comparison threshold are stored in
   a `WhenUnlockedThisDeviceOnly` Keychain item.
6. Raw frames and face photographs are never written to disk or uploaded.

## Unlock policy

- A centered face must match the enrolled profile.
- A randomly selected left/right head turn must follow the match in the same session.
- Five quality-filtered mismatching frames constitute one failed attempt.
- Three failed sessions disable camera unlock until LocalAuthentication succeeds.
- Lock, sleep and session changes cancel capture and lock private widgets.
- Camera capture starts only after an explicit Unlock or Enrollment action and stops
  immediately after success, failure or cancellation.

## Explicit limitations

An RGB camera has no TrueDepth map, infrared illumination or Secure Enclave-bound
biometric matcher. Active head-turn liveness raises the cost of a photo replay but
cannot guarantee resistance to a high-quality video, mask or real-time deepfake.
System credentials, irreversible actions and macOS login therefore remain under
Apple LocalAuthentication.
