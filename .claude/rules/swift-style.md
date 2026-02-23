---
paths:
  - "Sources/**/*.swift"
  - "Helper/**/*.swift"
  - "Tests/**/*.swift"
---

# Swift Code Rules

- Use Swift 6 strict concurrency: `actor` for shared mutable state, `@Sendable` for closures crossing isolation boundaries
- `@MainActor` on all ObservableObject view models
- `async/await` over completion handlers except for XPC protocol methods (which must be @objc compatible)
- `// MARK: - Section` comments to organize file sections
- DocC comments (`///`) on all public types and functions
- `guard let` for early returns, avoid nested `if let`
- Prefer `struct` over `class` unless reference semantics are needed
- All errors go through typed enums conforming to `LocalizedError`
- No force unwraps (`!`) outside of tests
- No `print()` — use `os.Logger` with appropriate categories
