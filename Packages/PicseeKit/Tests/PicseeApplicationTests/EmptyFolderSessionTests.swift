import Testing
@testable import PicseeApplication

@Test @MainActor func sessionWithoutFolderSourceIsNotEmptyFolder() {
    #expect(!ViewerSession().isEmptyFolder)
}
