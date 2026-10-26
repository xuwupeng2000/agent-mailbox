import Foundation

@main struct SessionChecks {
    @MainActor static func main() {
        let box = MailboxCenter()
        assert(!box.canStart)
        box.topic = "讨论一个方案"
        assert(box.canStart)
        box.agentB = box.agentA
        assert(!box.canStart)
        box.agentB = "cursor"
        box.begin()
        assert(box.sessionActive && box.expected == "codex" && box.completedReplies == 0)
        let first = box.sessionID
        box.begin()
        assert(box.sessionID == first)
        box.togglePause()
        assert(box.phase == "已暂停")
        box.interject("补充约束")
        box.togglePause()
        assert(box.phase == "进行中")
        box.stop()
        assert(!box.sessionActive && box.phase == "已结束")
        box.begin()
        assert(box.sessionID != first && box.completedReplies == 0)
        box.stop()
        print("Session state checks passed")
    }
}
