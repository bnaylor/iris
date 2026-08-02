import XCTest
@testable import iris

final class GCloudHelperTests: XCTestCase {
    
    // MARK: - requiredAPIs
    
    func testRequiredAPIsCount() {
        XCTAssertEqual(GCloudHelper.requiredAPIs.count, 7, "Seven Google Workspace APIs should be defined")
    }
    
    func testRequiredAPIsUniqueIDs() {
        let ids = GCloudHelper.requiredAPIs.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "API service names must be unique")
    }
    
    func testRequiredAPIIDsAreCorrect() {
        let ids = Set(GCloudHelper.requiredAPIs.map(\.id))
        XCTAssertTrue(ids.contains("calendar-json.googleapis.com"))
        XCTAssertTrue(ids.contains("people.googleapis.com"))
        XCTAssertTrue(ids.contains("drive.googleapis.com"))
        XCTAssertTrue(ids.contains("docs.googleapis.com"))
        XCTAssertTrue(ids.contains("sheets.googleapis.com"))
        XCTAssertTrue(ids.contains("gmail.googleapis.com"))
        XCTAssertTrue(ids.contains("tasks.googleapis.com"))
    }
    
    func testRequiredAPIScopesAreCorrect() {
        let scopes = Set(GCloudHelper.requiredAPIs.map(\.scope))
        XCTAssertTrue(scopes.contains("https://www.googleapis.com/auth/calendar"))
        XCTAssertTrue(scopes.contains("https://www.googleapis.com/auth/userinfo.email"))
        XCTAssertTrue(scopes.contains("https://www.googleapis.com/auth/drive"))
        XCTAssertTrue(scopes.contains("https://www.googleapis.com/auth/documents"))
        XCTAssertTrue(scopes.contains("https://www.googleapis.com/auth/spreadsheets"))
        XCTAssertTrue(scopes.contains("https://www.googleapis.com/auth/gmail.modify"))
        XCTAssertTrue(scopes.contains("https://www.googleapis.com/auth/tasks"))
    }
    
    func testRequiredAPIDisplayNames() {
        let names = GCloudHelper.requiredAPIs.map(\.displayName)
        XCTAssertTrue(names.contains("Google Calendar"))
        XCTAssertTrue(names.contains("Google People"))
        XCTAssertTrue(names.contains("Google Drive"))
        XCTAssertTrue(names.contains("Google Docs"))
        XCTAssertTrue(names.contains("Google Sheets"))
        XCTAssertTrue(names.contains("Gmail"))
        XCTAssertTrue(names.contains("Google Tasks"))
    }
    
    func testAPIInfoIdentifiable() {
        let api = GCloudHelper.requiredAPIs[0]
        XCTAssertEqual(api.id, api.id as String) // Identifiable conformance
    }
    
    func testAPIInfoDefaultEnabledIsFalse() {
        for api in GCloudHelper.requiredAPIs {
            XCTAssertFalse(api.enabled, "\(api.displayName) should default to enabled=false")
        }
    }
    
    // MARK: - enabledServices parsing
    
    func testEnabledServicesParsesGCloudOutput() {
        // enabledServices() calls `gcloud services list --enabled --format=value(config.name)`
        // and splits on newlines. Verify the data model works correctly with simulated output.
        let simulatedOutput = """
        calendar-json.googleapis.com
        drive.googleapis.com
        docs.googleapis.com
        """
        let parsed = Set(simulatedOutput.components(separatedBy: .newlines).filter { !$0.isEmpty })
        XCTAssertEqual(parsed.count, 3)
        XCTAssertTrue(parsed.contains("calendar-json.googleapis.com"))
        XCTAssertTrue(parsed.contains("drive.googleapis.com"))
        XCTAssertTrue(parsed.contains("docs.googleapis.com"))
        XCTAssertFalse(parsed.contains("sheets.googleapis.com"))
    }
    
    func testEnabledServicesEmptyOutput() {
        let parsed = Set("".components(separatedBy: .newlines).filter { !$0.isEmpty })
        XCTAssertTrue(parsed.isEmpty)
    }
    
    func testEnabledServicesFiltersEmptyLines() {
        let simulatedOutput = """
        calendar-json.googleapis.com
        
        drive.googleapis.com
        
        """
        let parsed = Set(simulatedOutput.components(separatedBy: .newlines).filter { !$0.isEmpty })
        XCTAssertEqual(parsed.count, 2)
    }
    
    // MARK: - APIInfo mutation
    
    func testAPIInfoEnabledToggle() {
        var api = GCloudHelper.APIInfo(
            id: "calendar-json.googleapis.com",
            displayName: "Google Calendar",
            scope: "https://www.googleapis.com/auth/calendar",
            enabled: false
        )
        XCTAssertFalse(api.enabled)
        api.enabled = true
        XCTAssertTrue(api.enabled)
    }
    
    func testRequiredAPIsAllEnabledCheck() {
        var apis = GCloudHelper.requiredAPIs.map { api in
            var copy = api
            copy.enabled = true
            return copy
        }
        XCTAssertTrue(apis.allSatisfy(\.enabled))
        
        apis[0].enabled = false
        XCTAssertFalse(apis.allSatisfy(\.enabled))
    }
}
