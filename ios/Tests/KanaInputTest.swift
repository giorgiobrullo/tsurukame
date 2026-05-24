// Copyright 2026 David Sansome
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import UIKit
import XCTest

private final class StubTextFieldDelegate: NSObject, UITextFieldDelegate {}

class KanaInputTest: XCTestCase {
  private var kanaInput: KanaInput!
  private var textField: UITextField!
  private var stubDelegate: StubTextFieldDelegate!

  // Consonants that trigger sokuon doubling: every consonant except n/m.
  private static let tsuConsonants: [String] =
    "bcdfghjklmnpqrstvwxyz".filter { !"nm".contains($0) }.map(String.init)
  private static let nCharacters = ["n", "m"]

  private static func canFollowN(_ consonant: String) -> Bool {
    guard let scalar = consonant.unicodeScalars.first else { return false }
    return kanaCanFollowN.contains(scalar)
  }

  override func setUp() {
    super.setUp()
    stubDelegate = StubTextFieldDelegate()
    kanaInput = KanaInput(delegate: stubDelegate)
    kanaInput.enabled = true
    textField = UITextField()
  }

  // MARK: - Table invariant

  func testReplacementsContainOnlyValidCombinations() {
    var lastKey: String?
    for key in kanaReplacements.keys.sorted(by: { $0.localizedCompare($1) == .orderedAscending }) {
      if let lastKey = lastKey {
        XCTAssertFalse(key.hasPrefix(lastKey), "'\(key)' has prefix '\(lastKey)'")
      }
      lastKey = key
    }
  }

  // MARK: - Delegate behaviour

  func testShouldChangeCharactersDoesNothingWhenDisabled() {
    let text = textField.text
    kanaInput.enabled = false
    let result = kanaInput.textField(textField,
                                     shouldChangeCharactersIn: NSRange(location: 0, length: 0),
                                     replacementString: "")
    XCTAssertTrue(result)
    XCTAssertEqual(text, textField.text)
  }

  func testShouldChangeCharactersDoesNothingOnPaste() {
    let text = textField.text
    let result = kanaInput.textField(textField,
                                     shouldChangeCharactersIn: NSRange(location: 0, length: 3),
                                     replacementString: "")
    XCTAssertTrue(result)
    XCTAssertEqual(text, textField.text)
  }

  func testReplacesSameConsonantWithSokuon() {
    for consonant in Self.tsuConsonants {
      textField.text = consonant
      let result = kanaInput.textField(textField,
                                       shouldChangeCharactersIn: NSRange(location: 1, length: 0),
                                       replacementString: consonant)
      XCTAssertTrue(result)
      XCTAssertEqual("っ", textField.text, "consonant \(consonant)")
    }
  }

  func testReplacesNFollowedByConsonant() {
    for consonant in Self.tsuConsonants where !Self.canFollowN(consonant) {
      for nm in Self.nCharacters {
        textField.text = nm
        let result = kanaInput.textField(textField,
                                         shouldChangeCharactersIn: NSRange(location: 1, length: 0),
                                         replacementString: consonant)
        XCTAssertTrue(result)
        XCTAssertEqual("ん", textField.text, "\(nm)+\(consonant)")
      }
    }
  }

  func testReplacesRomanizationPatternsCorrectly() {
    for (key, expected) in kanaReplacements {
      // "n " is handled by the n-followed-by-consonant path, tested separately.
      if key == "n " { continue }
      let lastCharacter = String(key.suffix(1))
      let prefix = String(key.dropLast())
      textField.text = prefix
      let result = kanaInput.textField(textField,
                                       shouldChangeCharactersIn:
                                       NSRange(location: (prefix as NSString).length, length: 0),
                                       replacementString: lastCharacter)
      XCTAssertFalse(result, "key '\(key)'")
      XCTAssertEqual(expected, textField.text, "key '\(key)'")
    }
  }

  func testReplacesSameUppercaseConsonantWithKatakanaSokuon() {
    for consonant in Self.tsuConsonants {
      let upper = consonant.uppercased()
      textField.text = upper
      let result = kanaInput.textField(textField,
                                       shouldChangeCharactersIn: NSRange(location: 1, length: 0),
                                       replacementString: upper)
      XCTAssertTrue(result)
      XCTAssertEqual("ッ", textField.text, "consonant \(upper)")
    }
  }

  func testReplacesUppercaseNFollowedByConsonantWithKatakana() {
    for consonant in Self.tsuConsonants where !Self.canFollowN(consonant) {
      for nm in Self.nCharacters {
        textField.text = nm.uppercased()
        let result = kanaInput.textField(textField,
                                         shouldChangeCharactersIn: NSRange(location: 1, length: 0),
                                         replacementString: consonant)
        XCTAssertTrue(result)
        XCTAssertEqual("ン", textField.text, "\(nm)+\(consonant)")
      }
    }
  }

  // MARK: - Bulk conversion function

  func testConvertKanaTextConvertsFully() {
    var convertedAll = false
    XCTAssertEqual(TKMConvertKanaText("ka", &convertedAll), "か")
    XCTAssertTrue(convertedAll)
    XCTAssertEqual(TKMConvertKanaText("kya", &convertedAll), "きゃ")
    XCTAssertEqual(TKMConvertKanaText("tta", &convertedAll), "った")
    XCTAssertEqual(TKMConvertKanaText("nn", &convertedAll), "ん")
    XCTAssertEqual(TKMConvertKanaText("wo", &convertedAll), "を")
    XCTAssertEqual(TKMConvertKanaText("shi", &convertedAll), "し")
  }

  func testConvertKanaTextFlagsTrailingLatin() {
    var convertedAll = true
    XCTAssertEqual(TKMConvertKanaText("kak", &convertedAll), "か")
    XCTAssertFalse(convertedAll)
  }

  func testConvertKanaTextAcceptsNilFlag() {
    XCTAssertEqual(TKMConvertKanaText("sushi", nil), "すし")
  }
}
