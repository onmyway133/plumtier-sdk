import Testing
@testable import Plumtier

@Test func versionIsSet()
{
    #expect(!Plumtier.version.isEmpty)
}
