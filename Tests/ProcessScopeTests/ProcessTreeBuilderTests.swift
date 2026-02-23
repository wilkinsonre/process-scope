import XCTest
@testable import ProcessScope

final class ProcessTreeBuilderTests: XCTestCase {

    func testBuildTreeFromFlatList() {
        let processes = [
            ProcessRecord(pid: 1, ppid: 0, name: "launchd", user: "root", uid: 0),
            ProcessRecord(pid: 100, ppid: 1, name: "WindowServer", user: "root", uid: 0),
            ProcessRecord(pid: 200, ppid: 1, name: "loginwindow", user: "root", uid: 0),
            ProcessRecord(pid: 300, ppid: 200, name: "Finder", user: "user", uid: 501),
            ProcessRecord(pid: 400, ppid: 200, name: "Dock", user: "user", uid: 501),
        ]

        let tree = ProcessTreeBuilder.buildTree(from: processes)
        XCTAssertFalse(tree.isEmpty)

        // launchd should be root
        let launchd = tree.first { $0.process.name == "launchd" }
        XCTAssertNotNil(launchd)
        XCTAssertEqual(launchd?.children.count, 2) // WindowServer + loginwindow

        // loginwindow should have Finder and Dock as children
        let loginwindow = launchd?.children.first { $0.process.name == "loginwindow" }
        XCTAssertNotNil(loginwindow)
        XCTAssertEqual(loginwindow?.children.count, 2)
    }

    func testFlattenTree() {
        let processes = [
            ProcessRecord(pid: 1, ppid: 0, name: "root", user: "root", uid: 0),
            ProcessRecord(pid: 2, ppid: 1, name: "child1", user: "root", uid: 0),
            ProcessRecord(pid: 3, ppid: 1, name: "child2", user: "root", uid: 0),
            ProcessRecord(pid: 4, ppid: 2, name: "grandchild", user: "root", uid: 0),
        ]

        let tree = ProcessTreeBuilder.buildTree(from: processes)
        let flat = ProcessTreeBuilder.flatten(tree)
        XCTAssertEqual(flat.count, 4)
    }

    func testFindPIDInTree() {
        let processes = [
            ProcessRecord(pid: 1, ppid: 0, name: "root", user: "root", uid: 0),
            ProcessRecord(pid: 2, ppid: 1, name: "child", user: "root", uid: 0),
            ProcessRecord(pid: 3, ppid: 2, name: "grandchild", user: "root", uid: 0),
        ]

        let tree = ProcessTreeBuilder.buildTree(from: processes)
        let found = ProcessTreeBuilder.find(pid: 3, in: tree)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.process.name, "grandchild")
    }

    func testParentChain() {
        let processes = [
            ProcessRecord(pid: 1, ppid: 0, name: "root", user: "root", uid: 0),
            ProcessRecord(pid: 2, ppid: 1, name: "middle", user: "root", uid: 0),
            ProcessRecord(pid: 3, ppid: 2, name: "leaf", user: "root", uid: 0),
        ]

        let tree = ProcessTreeBuilder.buildTree(from: processes)
        let chain = ProcessTreeBuilder.parentChain(for: 3, in: tree)
        XCTAssertEqual(chain.count, 3)
        XCTAssertEqual(chain.first?.process.name, "root")
        XCTAssertEqual(chain.last?.process.name, "leaf")
    }

    func testEmptyProcessList() {
        let tree = ProcessTreeBuilder.buildTree(from: [])
        XCTAssertTrue(tree.isEmpty)
    }

    func testOrphanProcesses() {
        // Processes whose parent isn't in the list
        let processes = [
            ProcessRecord(pid: 500, ppid: 999, name: "orphan1", user: "user", uid: 501),
            ProcessRecord(pid: 600, ppid: 999, name: "orphan2", user: "user", uid: 501),
        ]

        let tree = ProcessTreeBuilder.buildTree(from: processes)
        XCTAssertEqual(tree.count, 2) // Both should be roots
    }
}
