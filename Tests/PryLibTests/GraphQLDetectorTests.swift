import XCTest
@testable import PryLib

final class GraphQLDetectorTests: XCTestCase {
    func testDetectGraphQLBody() {
        let body = "{\"query\":\"{ users { name } }\",\"operationName\":\"GetUsers\"}"
        let info = GraphQLDetector.detect(body: body)
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.operationName, "GetUsers")
    }

    func testDetectGraphQLNoOperation() {
        let body = "{\"query\":\"{ users { name } }\"}"
        let info = GraphQLDetector.detect(body: body)
        XCTAssertNotNil(info)
        XCTAssertNil(info?.operationName)
        XCTAssertTrue(info!.query.contains("users"))
    }

    func testNotGraphQL() {
        let body = "{\"key\":\"value\"}"
        let info = GraphQLDetector.detect(body: body)
        XCTAssertNil(info)
    }

    func testExtractOperationName() {
        let body = "{\"query\":\"mutation CreateUser($name: String!) { createUser(name: $name) { id } }\",\"operationName\":\"CreateUser\",\"variables\":{\"name\":\"John\"}}"
        let info = GraphQLDetector.detect(body: body)
        XCTAssertEqual(info?.operationName, "CreateUser")
        XCTAssertNotNil(info?.variables)
    }

    func testNilBody() {
        let info = GraphQLDetector.detect(body: nil)
        XCTAssertNil(info)
    }
}
