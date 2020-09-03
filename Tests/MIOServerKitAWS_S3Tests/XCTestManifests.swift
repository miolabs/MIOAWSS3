import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(MIOServerKitAWS_S3Tests.allTests),
    ]
}
#endif
