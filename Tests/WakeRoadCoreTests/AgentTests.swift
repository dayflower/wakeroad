import XCTest
@testable import WakeRoadCore

final class AgentTests: XCTestCase {
    private var home: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    func testResolvesKnownAgentsFromTranscriptPaths() {
        XCTAssertEqual(
            Agent.agent(forTranscriptPath: home + "/.claude/projects/foo/session.jsonl")?.name,
            "Claude Code"
        )
        XCTAssertEqual(
            Agent.agent(forTranscriptPath: home + "/.codex/sessions/2026/07/18/rollout.jsonl")?.name,
            "Codex"
        )
    }

    func testUnknownPathYieldsNil() {
        XCTAssertNil(Agent.agent(forTranscriptPath: home + "/somewhere/else/file.jsonl"))
        XCTAssertNil(Agent.agent(forTranscriptPath: "/var/log/other.jsonl"))
    }

    func testTranscriptExtensionsCoverAllKnownAgents() {
        for agent in Agent.known {
            XCTAssertTrue(Agent.transcriptExtensions.contains(agent.fileExtension))
        }
    }
}
