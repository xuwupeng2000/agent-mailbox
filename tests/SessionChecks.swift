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
        let replies = box.completedReplies
        let phase = box.phase
        _ = L10n.text(.endSession, .en)
        _ = L10n.text(.endSession, .zhHant)
        assert(box.sessionID == first && box.completedReplies == replies && box.phase == phase)
        box.begin()
        assert(box.sessionID == first)
        box.togglePause()
        assert(box.phase == .paused)
        box.interject("补充约束")
        box.togglePause()
        assert(box.phase == .running)
        box.stop()
        assert(!box.sessionActive && box.phase == .stopped)
        box.begin()
        assert(box.sessionID != first && box.completedReplies == 0)
        box.stop()
        checkRoundsReportsAndSearch()
        checkCopy()
        print("Session state checks passed")
    }

    @MainActor static func checkRoundsReportsAndSearch() {
        let history = MailboxCenter()
        history.topic = "查找分隔"
        history.agentB = "cursor"
        history.rounds = 2
        history.begin()
        let sid = history.sessionID
        func note(_ sender: String, _ recipient: String, _ body: String) -> String {
            history.acceptWrite(recipient: recipient, body: "FROM \(sender)\nSESSION \(sid)\n\(body)\n<<<END>>>\n")
        }
        assert(note("codex", "cursor", "alpha keyword") == "OK")
        assert(note("cursor", "codex", "beta") == "OK")
        assert(history.turns.map(\.round) == [1, 1])
        assert(history.phase == .running)
        assert(note("codex", "cursor", "gamma keyword") == "OK")
        assert(note("cursor", "codex", "delta") == "OK")
        assert(history.phase == .reporting)
        assert(history.sessionActive)
        assert(history.turns.map(\.round) == [1, 1, 2, 2])
        assert(note("codex", "cursor", "too late") != "OK")
        assert(note("codex", "user", "wrote the separator") == "OK")
        assert(history.turns.contains { $0.isReport && $0.text.contains("wrote the separator") })
        assert(history.phase == .reporting && history.turns.count == 5)
        assert(note("codex", "user", "again") != "OK")
        assert(note("cursor", "user", "added search") == "OK")
        assert(history.phase == .completed && !history.sessionActive)
        assert(history.turns.filter(\.isReport).count == 2)
        let keptTurns = history.turns.count
        assert(ConversationSearch.matches(sender: "codex", recipient: "cursor", text: "alpha keyword", query: "KEYWORD"))
        assert(!ConversationSearch.matches(sender: "codex", recipient: "cursor", text: "alpha keyword", query: "missing"))
        assert(history.turns.count == keptTurns && history.sessionID == sid)

        let ending = MailboxCenter()
        ending.topic = "结束"
        ending.agentB = "cursor"
        ending.begin()
        let endingID = ending.sessionID
        assert(ending.acceptWrite(recipient: "cursor", body: "FROM codex\nSESSION \(endingID)\n保持这条\n<<<END>>>\n") == "OK")
        ending.endSession()
        assert(ending.phase == .reporting && ending.sessionActive && ending.sessionID == endingID && ending.turns.count == 1)
        ending.endSession()
        assert(!ending.sessionActive && ending.phase == .stopped && ending.sessionID == endingID && ending.turns.count == 1)

        let reader = MailboxCenter()
        reader.markReading("cursor")
        assert(reader.reading == ["cursor"])
        reader.markReading("cursor")
        reader.markReading("codex")
        assert(reader.reading == ["cursor", "codex"])
        reader.finishReading("cursor")
        assert(reader.reading == ["codex"])
        reader.topic = "读取提示"
        reader.begin()
        assert(reader.reading.isEmpty)
    }

    static func checkCopy() {
        for language in AppLanguage.allCases {
            for key in L10n.Key.allCases {
                let value = L10n.text(key, language)
                assert(!value.isEmpty, "\(language.rawValue) \(key.rawValue)")
                if language == .en {
                    let hasHan = value.unicodeScalars.contains { scalar in
                        (0x4E00...0x9FFF).contains(scalar.value)
                    }
                    assert(!hasHan, key.rawValue)
                }
            }
        }
        assert(L10n.text(.openMainWindow, .zhHant) == "打開主視窗")
        assert(L10n.text(.portClosed, .zhHant).contains("連接埠"))
        assert(L10n.status(.open, .zhHant, port: 9777).contains("記憶體"))
        assert(L10n.text(.languageNote, .en).contains("does not translate"))
        for language in AppLanguage.allCases {
            assert(L10n.text(.appTitle, language) == "Agent Mailbox")
        }
        let english = L10n.instructions(name: "cursor", peer: "codex", language: .en)
        for token in ["wait", "write", "SESSION", "<<<TIMEOUT>>>", "<<<STOP>>>", "ERR", "AGENT_README.md"] {
            assert(english.contains(token), token)
        }
        assert(!english.contains("\n<<<END>>>\n"))
        for language in AppLanguage.allCases {
            let note = L10n.instructions(name: "codex", peer: "cursor", language: language)
            assert(note.contains("Contents/MacOS/mailbox"))
            assert(note.contains("Contents/Resources/AGENT_README.md"))
            assert(!note.contains("python3"))
        }
        let opening = L10n.openingBody(topic: "Keep this topic", rounds: 2, language: .en)
        assert(opening.contains("Keep this topic"))
        assert(!opening.contains("<<<END>>>"))
        let traditional = L10n.openingBody(topic: "保留話題", rounds: 2, language: .zhHant)
        assert(traditional.contains("保留話題"))
        assert(traditional.contains("輪"))
        assert(L10n.rounds(12, .en).contains("12"))
        assert(L10n.progress(phase: .paused, replies: 1, next: "codex", language: .en).contains("Paused"))
        assert(L10n.progress(phase: .paused, replies: 1, next: "codex", language: .en).contains("codex"))
        assert(english.contains("write --to user"))
        assert(english.contains("actions"))
        assert(L10n.roundTitle(2, .zhHant).contains("輪"))
        assert(!L10n.reportRequest(.en).contains("<<<END>>>"))
        assert(L10n.readingStatus("cursor", .zhHans) == "cursor 已经开始读取")
        assert(L10n.readingStatus("cursor", .zhHant) == "cursor 已經開始讀取")
        assert(L10n.readingStatus("cursor", .en) == "cursor has started reading")
        assert(english.contains("has started reading"))
        assert(english.contains("spends no tokens"))
        assert(english.contains("Do not poll"))
        assert(english.contains("cursor"))
    }
}
