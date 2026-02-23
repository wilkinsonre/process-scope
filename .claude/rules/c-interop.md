---
paths:
  - "Sources/Utilities/CInterop/**/*.swift"
---

# C Interop Safety Rules

- ALWAYS use `defer { buffer.deallocate() }` after any manual allocation
- ALWAYS check return values from sysctl, proc_pidinfo, IOServiceGetMatchingServices
- NEVER call C APIs outside of Sources/Utilities/CInterop/ — all C access goes through wrappers
- Return `Optional` (nil) on failure, never crash
- Use `withUnsafeMutablePointer` and `withMemoryRebound` for type-safe pointer casts
- Document the memory layout of C structs in comments (especially KERN_PROCARGS2)
- Size calculations: always use `MemoryLayout<T>.size` or `.stride`, never hardcode
