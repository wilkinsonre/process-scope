import XCTest
@testable import ProcessScope

final class ProcessEnricherTests: XCTestCase {
    var enricher: ProcessEnricher!

    override func setUp() {
        enricher = ProcessEnricher(rules: ProcessEnricher.defaultRules)
    }

    func testPythonUvicornEnrichment() {
        let proc = ProcessRecord(
            pid: 100, ppid: 1, name: "python3",
            executablePath: "/usr/bin/python3",
            arguments: ["/usr/bin/python3", "-m", "uvicorn", "atlas.main:app", "--port", "8080"],
            user: "dev", uid: 501
        )
        let label = enricher.enrich(proc)
        XCTAssertNotNil(label)
        XCTAssertTrue(label?.contains("uvicorn") ?? false)
        XCTAssertTrue(label?.contains("atlas.main:app") ?? false)
    }

    func testPythonDjangoEnrichment() {
        let proc = ProcessRecord(
            pid: 101, ppid: 1, name: "python3",
            arguments: ["python3", "manage.py", "runserver"],
            workingDirectory: "/Users/dev/myproject",
            user: "dev", uid: 501
        )
        let label = enricher.enrich(proc)
        XCTAssertNotNil(label)
        XCTAssertTrue(label?.contains("Django") ?? false)
    }

    func testNodeNextJSEnrichment() {
        let proc = ProcessRecord(
            pid: 102, ppid: 1, name: "node",
            arguments: ["node", "/Users/dev/app/node_modules/.bin/next", "dev"],
            workingDirectory: "/Users/dev/app",
            user: "dev", uid: 501
        )
        let label = enricher.enrich(proc)
        XCTAssertNotNil(label)
        XCTAssertTrue(label?.contains("Next.js") ?? false)
    }

    func testSSHEnrichment() {
        let proc = ProcessRecord(
            pid: 103, ppid: 1, name: "ssh",
            arguments: ["ssh", "user@example.com", "-p", "2222"],
            user: "dev", uid: 501
        )
        let label = enricher.enrich(proc)
        XCTAssertNotNil(label)
        XCTAssertTrue(label?.contains("SSH") ?? false)
    }

    func testDockerDesktopEnrichment() {
        let proc = ProcessRecord(
            pid: 104, ppid: 1, name: "com.docker.backend",
            arguments: ["com.docker.backend"],
            user: "dev", uid: 501
        )
        let label = enricher.enrich(proc)
        XCTAssertEqual(label, "Docker Desktop")
    }

    func testNoMatchReturnsNil() {
        let proc = ProcessRecord(
            pid: 105, ppid: 1, name: "some_unknown_process",
            arguments: ["some_unknown_process"],
            user: "dev", uid: 501
        )
        let label = enricher.enrich(proc)
        XCTAssertNil(label)
    }

    func testBatchEnrichment() {
        let processes = [
            ProcessRecord(pid: 100, ppid: 1, name: "python3",
                         arguments: ["/usr/bin/python3", "-m", "uvicorn", "app:main"],
                         user: "dev", uid: 501),
            ProcessRecord(pid: 101, ppid: 1, name: "node",
                         arguments: ["node", "server.js"],
                         user: "dev", uid: 501),
            ProcessRecord(pid: 102, ppid: 1, name: "unknown",
                         arguments: ["unknown"],
                         user: "dev", uid: 501),
        ]
        let results = enricher.enrichBatch(processes)
        XCTAssertEqual(results.count, 2) // unknown should not match
        XCTAssertNotNil(results[100])
        XCTAssertNotNil(results[101])
        XCTAssertNil(results[102])
    }
}
