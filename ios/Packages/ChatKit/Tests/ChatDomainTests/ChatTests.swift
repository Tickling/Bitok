import Foundation
import Testing
import CoreDomain
@testable import ChatDomain

@Suite("Чат")
struct ChatTests {
    let chat = ID<Chat>()
    let me = UserID()

    func message(_ seq: Int64, client: UUID = UUID()) -> Message {
        Message(id: ID(), chatId: chat, senderId: me, clientMessageId: client, sequence: seq,
                kind: .text, text: "msg \(seq)", createdAt: Date())
    }

    @Test("Ретрай с тем же clientMessageId не создаёт дубликат, порядок — по sequence")
    func mergeDeduplicatesAndOrders() {
        let client = UUID()
        let merged = mergeMessages([message(2), message(1, client: client)], with: [message(1, client: client), message(3)])
        #expect(merged.map(\.sequence) == [1, 2, 3])
    }

    @Test func onlyRecipientAnswersInvitation() throws {
        let to = UserID()
        var invitation = PlayInvitation(id: ID(), fromId: me, toId: to, type: .friendlyGame, clubId: ClubID(), proposedAt: Date())
        #expect(throws: InvitationError.notRecipient) { try invitation.answer(by: me, accept: true) }
        try invitation.answer(by: to, accept: true)
        #expect(invitation.status == .accepted)
        #expect(throws: InvitationError.alreadyAnswered) { try invitation.answer(by: to, accept: false) }
    }

    @Test func hiddenProgressShowsLock() {
        let card = PlayerCard(id: UserID(), displayName: "Дмитрий Л.", levelTitle: "Любитель")
        #expect(card.isProgressHidden)
    }
}
