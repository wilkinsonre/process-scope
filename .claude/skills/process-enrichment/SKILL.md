---
name: process-enrichment
description: Process identification and enrichment engine. Use when implementing the ProcessEnricher, parsing command-line arguments into enriched labels, building the process tree, implementing project grouping, or adding new enrichment rules.
---

# Process Enrichment Engine

The core differentiator. Turns opaque process names into meaningful labels.

## Enrichment Pipeline

```
Raw Process (pid, name, ppid)
    │
    ▼
┌─ KERN_PROCARGS2 ──────────────────┐
│  exec_path, argv[], env vars       │
└────────────────────────────────────┘
    │
    ▼
┌─ proc_pidinfo ─────────────────────┐
│  working directory, open FDs        │
└────────────────────────────────────┘
    │
    ▼
┌─ Rule Engine ──────────────────────┐
│  Match argv patterns → label       │
│  Detect listening ports            │
│  Resolve Docker container names    │
└────────────────────────────────────┘
    │
    ▼
EnrichedProcess(label: "uvicorn atlas.main:app (port 8080)")
```

## Data Model

```swift
struct EnrichedProcess: Identifiable {
    let pid: pid_t
    let ppid: pid_t
    let rawName: String
    let executablePath: String?
    let arguments: [String]
    let workingDirectory: String?
    let enrichedLabel: String       // ← The money field
    let icon: String                // SF Symbol name
    let projectPath: String?        // Inferred project root
    let cpuPercent: Double
    let rssBytes: UInt64
    let networkIO: NetworkIO?
    let children: [EnrichedProcess]
    
    var id: pid_t { pid }
}
```

## Rule Engine

```swift
struct EnrichmentRule: Codable {
    struct Match: Codable {
        var processName: String?       // exact match on process name
        var argvContains: String?      // substring in joined argv
        var argvRegex: String?         // regex against joined argv
        var envContains: String?       // key=value in environment
    }
    
    let match: Match
    let labelTemplate: String          // with {placeholders}
    let icon: String                   // SF Symbol name
}
```

### Template Placeholders

| Placeholder | Meaning | Example |
|------------|---------|---------|
| `{argv_after:X\|first}` | First arg after X | `uvicorn {argv_after:uvicorn\|first}` → `uvicorn atlas.main:app` |
| `{argv_value:--flag\|default:Y}` | Value of --flag | `(port {argv_value:--port\|default:8000})` |
| `{argv_match_basename}` | Basename of regex match | `python → {argv_match_basename}` → `python → train.py` |
| `{cwd_basename}` | Working dir basename | `{cwd_basename}/next dev` |
| `{env:VAR}` | Environment variable | `({env:VIRTUAL_ENV})` |
| `{port}` | Detected listening port | `(port {port})` |

### Placeholder Resolution

```swift
func resolveTemplate(_ template: String, context: EnrichmentContext) -> String {
    var result = template
    
    // {argv_after:X|first}
    let argvAfterPattern = /\{argv_after:(\w+)\|first\}/
    for match in result.matches(of: argvAfterPattern) {
        let keyword = String(match.1)
        if let idx = context.argv.firstIndex(where: { $0.contains(keyword) }),
           idx + 1 < context.argv.count {
            result = result.replacing(match.0, with: context.argv[idx + 1])
        }
    }
    
    // {argv_value:--flag|default:Y}
    let flagPattern = /\{argv_value:(--[\w-]+)\|default:(\w+)\}/
    for match in result.matches(of: flagPattern) {
        let flag = String(match.1)
        let defaultVal = String(match.2)
        if let idx = context.argv.firstIndex(of: flag), idx + 1 < context.argv.count {
            result = result.replacing(match.0, with: context.argv[idx + 1])
        } else {
            result = result.replacing(match.0, with: defaultVal)
        }
    }
    
    // ... other placeholder types
    return result
}
```

## Built-in Rules (DefaultEnrichmentRules.yaml)

```yaml
rules:
  # Python
  - match: { process_name: "python3", argv_contains: "uvicorn" }
    label: "uvicorn {argv_after:uvicorn|first} (port {argv_value:--port|default:8000})"
    icon: "server.rack"
  
  - match: { process_name: "python3", argv_contains: "celery" }
    label: "celery {argv_after:celery|first} {argv_after:-A|first}"
    icon: "arrow.triangle.2.circlepath"
  
  - match: { process_name: "python3", argv_contains: "manage.py" }
    label: "django {argv_after:manage.py|first}"
    icon: "globe"
  
  - match: { process_name: "python3", argv_contains: "gunicorn" }
    label: "gunicorn {argv_after:gunicorn|first} (port {argv_value:-b|default:8000})"
    icon: "server.rack"
  
  - match: { process_name: "python3", argv_contains: "flask" }
    label: "flask (port {argv_value:--port|default:5000})"
    icon: "globe"
  
  - match: { process_name: "python3", argv_contains: "pytest" }
    label: "pytest {argv_after:pytest|first}"
    icon: "checkmark.circle"
  
  - match: { process_name: "python3", argv_regex: ".*\\.py$" }
    label: "python → {argv_match_basename}"
    icon: "terminal"
  
  # Node.js
  - match: { process_name: "node", argv_contains: "next" }
    label: "next {argv_after:next|first} (port {argv_value:-p|argv_value:--port|default:3000})"
    icon: "globe"
  
  - match: { process_name: "node", argv_contains: "vite" }
    label: "vite {argv_after:vite|first} (port {argv_value:--port|default:5173})"
    icon: "bolt.fill"
  
  - match: { process_name: "node", argv_contains: "ts-node" }
    label: "ts-node → {argv_after:ts-node|first}"
    icon: "terminal"
  
  - match: { process_name: "node", argv_contains: "webpack" }
    label: "webpack {argv_after:webpack|first}"
    icon: "shippingbox"
  
  - match: { process_name: "node", argv_contains: "esbuild" }
    label: "esbuild"
    icon: "bolt.fill"
  
  # Ruby
  - match: { process_name: "ruby", argv_contains: "rails" }
    label: "rails {argv_after:rails|first}"
    icon: "tram"
  
  - match: { process_name: "ruby", argv_contains: "puma" }
    label: "puma (port {argv_value:-p|default:3000})"
    icon: "server.rack"
  
  # Java
  - match: { process_name: "java", argv_contains: "-jar" }
    label: "java → {argv_after:-jar|first}"
    icon: "cup.and.saucer"
  
  - match: { process_name: "java", argv_contains: "gradle" }
    label: "gradle {argv_after:gradle|first}"
    icon: "hammer"
  
  # Go
  - match: { process_name: "go", argv_contains: "run" }
    label: "go run {argv_after:run|first}"
    icon: "hare"
  
  # Docker
  - match: { process_name: "com.docker.backend" }
    label: "Docker Engine"
    icon: "shippingbox.fill"
  
  # AI/ML
  - match: { process_name: "ollama", argv_contains: "serve" }
    label: "ollama serve"
    icon: "brain"
  
  - match: { process_name: "python3", argv_contains: "mlx" }
    label: "MLX {argv_after:mlx|first}"
    icon: "brain.head.profile"
  
  # Elixir
  - match: { process_name: "beam.smp" }
    label: "elixir/erlang BEAM"
    icon: "waveform"
  
  # Universal: listening port detection (applied last as fallback enrichment)
  # This is handled in code, not YAML — appends (port N) to any process with a listening socket
```

## Process Tree Building

```swift
func buildTree(from processes: [ProcessRecord]) -> [EnrichedProcess] {
    // 1. Index by PID
    var byPID: [pid_t: ProcessRecord] = [:]
    for proc in processes { byPID[proc.pid] = proc }
    
    // 2. Group children by PPID
    var childrenOf: [pid_t: [pid_t]] = [:]
    for proc in processes {
        childrenOf[proc.ppid, default: []].append(proc.pid)
    }
    
    // 3. Recursive enrichment from root
    func enrich(_ pid: pid_t) -> EnrichedProcess? {
        guard let proc = byPID[pid] else { return nil }
        let children = (childrenOf[pid] ?? []).compactMap { enrich($0) }
        let label = enrichmentEngine.enrich(proc)
        return EnrichedProcess(/* ... */, children: children)
    }
    
    // Root: PID 1 (launchd) or all processes with ppid=0/1
    return (childrenOf[1] ?? []).compactMap { enrich($0) }
}
```

## Project Grouping Algorithm

```swift
func groupByProject(_ processes: [EnrichedProcess]) -> [ProjectGroup] {
    // 1. Collect all working directories
    let workDirs = processes.compactMap { $0.workingDirectory }
    
    // 2. Find common ancestors (potential project roots)
    // Heuristic: directories containing .git, package.json, Cargo.toml, etc.
    let projectMarkers = [".git", "package.json", "Cargo.toml", "go.mod", 
                          "Pipfile", "pyproject.toml", "Gemfile", ".xcodeproj"]
    
    // 3. Walk up from each working directory until we find a marker
    var projectRoots: Set<String> = []
    for dir in workDirs {
        var current = dir
        while current != "/" {
            if projectMarkers.contains(where: { FileManager.default.fileExists(atPath: "\(current)/\($0)") }) {
                projectRoots.insert(current)
                break
            }
            current = (current as NSString).deletingLastPathComponent
        }
    }
    
    // 4. Assign processes to project roots
    // 5. Include Docker containers matched by compose project labels
    // 6. Aggregate resource usage per group
}
```

## Docker Container Matching

```swift
func matchContainerToProject(_ container: DockerContainer) -> String? {
    // Check compose project label
    if let project = container.labels["com.docker.compose.project"] {
        return project
    }
    // Check compose working dir label
    if let workDir = container.labels["com.docker.compose.project.working_dir"] {
        return workDir
    }
    return nil
}
```
