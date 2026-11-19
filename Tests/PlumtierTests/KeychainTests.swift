import Foundation
import Testing
@testable import Plumtier

@Test func keychainRoundTrip()
{
    let store = KeychainStore(service: "plumtier.tests.\(UUID().uuidString)")
    store.write(Data("one".utf8), "item")
    #expect(store.read("item") == Data("one".utf8))
    store.write(Data("two".utf8), "item")
    #expect(store.read("item") == Data("two".utf8))
    store.delete("item")
    #expect(store.read("item") == nil)
}
