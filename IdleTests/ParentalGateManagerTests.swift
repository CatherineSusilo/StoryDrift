//
//  ParentalGateManagerTests.swift
//  StoryDrift
//
//  Verifies passcode hashing, parent-mode persistence, default-PIN seeding,
//  and child-mode toggle. Documents the auto-lock-on-background gap.
//

import XCTest
@testable import Idle

@MainActor
final class ParentalGateManagerTests: XCTestCase {

    private let kPasscodeHash = "parentalGate.passcodeHash"
    private let kIsParentMode = "parentalGate.isParentMode"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: kPasscodeHash)
        UserDefaults.standard.removeObject(forKey: kIsParentMode)
    }

    func test_init_seedsDefault000000PasscodeWhenNoneStored() {
        let m = ParentalGateManager()
        // Default PIN "000000" must verify
        XCTAssertTrue(m.verify("000000"))
        XCTAssertFalse(m.verify("123456"))
    }

    func test_init_restoresParentModeFromUserDefaults() {
        UserDefaults.standard.set(true, forKey: kIsParentMode)
        let m = ParentalGateManager()
        XCTAssertTrue(m.isParentMode)
    }

    func test_init_defaultsToChildModeWhenNothingStored() {
        let m = ParentalGateManager()
        XCTAssertFalse(m.isParentMode)
    }

    func test_setPasscode_replacesHash_andEntersParentMode() {
        let m = ParentalGateManager()
        m.setPasscode("424242")
        XCTAssertTrue(m.verify("424242"))
        XCTAssertFalse(m.verify("000000"))
        XCTAssertTrue(m.isParentMode)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: kIsParentMode))
    }

    func test_enterChildMode_persists() {
        let m = ParentalGateManager()
        m.enterParentMode()
        XCTAssertTrue(m.isParentMode)
        m.enterChildMode()
        XCTAssertFalse(m.isParentMode)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: kIsParentMode))
    }

    func test_verify_rejectsEmptyPin() {
        let m = ParentalGateManager()
        XCTAssertFalse(m.verify(""))
    }

    func test_verify_rejectsPinOfWrongLength() {
        let m = ParentalGateManager()
        m.setPasscode("123456")
        // Documents the hashing-only check: "12345" hashes differently → false
        XCTAssertFalse(m.verify("12345"))
        XCTAssertFalse(m.verify("1234567"))
    }

    func test_resetPasscode_swapsPinAndEntersParentMode() {
        let m = ParentalGateManager()
        m.setPasscode("111111")
        m.enterChildMode()
        m.resetPasscode(newPin: "999999")
        XCTAssertTrue(m.verify("999999"))
        XCTAssertFalse(m.verify("111111"))
        XCTAssertTrue(m.isParentMode)
    }

    // ── Auto-lock on background ──────────────────────────────────────────────
    func test_enterParentMode_then_didEnterBackground_locksToChildMode() async {
        let m = ParentalGateManager()
        m.enterParentMode()
        XCTAssertTrue(m.isParentMode)

        #if canImport(UIKit)
        NotificationCenter.default.post(
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        // handler hops onto MainActor via Task — yield to let it run
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(m.isParentMode, "Backgrounding must auto-exit parent mode.")
        XCTAssertFalse(UserDefaults.standard.bool(forKey: kIsParentMode))
        #endif
    }
}
