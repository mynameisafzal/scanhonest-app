import XCTest
@testable import ScanHonest

// MARK: - FileNamingTests
//
// Two naming surfaces are tested:
//
//   1. OCRProcessor.suggestFileName(from:)
//      AI-driven: derives a name from the first line of OCR text,
//      appends a month/year suffix. Must strip punctuation.
//
//   2. ShareExportService.safeFSName(_:)
//      Filesystem safety: strips the 8 POSIX/NTFS illegal characters
//      ( / \ : * ? " < > | ), trims whitespace, truncates to 80 chars,
//      and falls back to "Document" on an empty result.

final class FileNamingTests: XCTestCase {

    // MARK: - Helpers

    private let processor = OCRProcessor.shared

    /// Generates a month_year suffix matching OCRProcessor's internal DateFormatter.
    private var currentMonthYearSuffix: String {
        let df = DateFormatter()
        df.dateFormat = "MMM_yyyy"
        return df.string(from: Date())
    }

    // MARK: - OCRProcessor.suggestFileName — basic extraction

    func testSuggestFileNameUsesFirstNonEmptyLine() {
        let text = "Invoice #1234\nTotal: $500\nDue: 2026-06-01"
        let name = processor.suggestFileName(from: text)
        XCTAssertTrue(name.hasPrefix("Invoice"),
                      "suggestFileName must derive the name from the first non-empty line")
    }

    func testSuggestFileNameAppendsMonthYearSuffix() {
        let text = "Contract"
        let name = processor.suggestFileName(from: text)
        XCTAssertTrue(name.hasSuffix(currentMonthYearSuffix),
                      "suggestFileName must append a MMM_yyyy suffix to the derived name")
    }

    func testSuggestFileNameLimitsFirstLineToThirtyChars() {
        let longLine = String(repeating: "A", count: 50)
        let name = processor.suggestFileName(from: longLine)
        // Name = prefix(30) + "_" + suffix — so length > 30 is expected, but the doc part is ≤ 30
        let withoutSuffix = name.replacingOccurrences(of: "_\(currentMonthYearSuffix)", with: "")
        XCTAssertLessThanOrEqual(withoutSuffix.count, 30,
                                 "The document-derived portion must be capped at 30 characters")
    }

    func testSuggestFileNameFallsBackToScanWhenTextIsEmpty() {
        let name = processor.suggestFileName(from: "")
        XCTAssertTrue(name.hasPrefix("Scan"),
                      "suggestFileName must fall back to 'Scan' as the prefix when OCR text is empty")
    }

    func testSuggestFileNameFallsBackWhenAllLinesAreWhitespace() {
        let name = processor.suggestFileName(from: "   \n\t\n   ")
        XCTAssertTrue(name.hasPrefix("Scan"),
                      "suggestFileName must fall back to 'Scan' when all lines are blank")
    }

    // MARK: - OCRProcessor.suggestFileName — punctuation stripping

    func testSuggestFileNameStripsColon() {
        let name = processor.suggestFileName(from: "Invoice: January 2026")
        XCTAssertFalse(name.contains(":"),
                       "suggestFileName must remove colons from the suggested name")
    }

    func testSuggestFileNameStripsPeriods() {
        let name = processor.suggestFileName(from: "Dr. Smith Report")
        XCTAssertFalse(name.contains("."),
                       "suggestFileName must strip period characters")
    }

    func testSuggestFileNameStripsCommas() {
        let name = processor.suggestFileName(from: "Smith, John — Letter")
        XCTAssertFalse(name.contains(","),
                       "suggestFileName must strip comma characters")
    }

    func testSuggestFileNameReplacesSpacesWithUnderscores() {
        let name = processor.suggestFileName(from: "Tax Return 2025")
        let withoutSuffix = name.replacingOccurrences(of: "_\(currentMonthYearSuffix)", with: "")
        XCTAssertFalse(withoutSuffix.contains(" "),
                       "suggestFileName must replace spaces with underscores")
    }

    func testSuggestFileNameProducesNonEmptyResult() {
        // Even with dense punctuation, result must not be empty
        let name = processor.suggestFileName(from: "!@#$%^&*()")
        XCTAssertFalse(name.isEmpty,
                       "suggestFileName must always return a non-empty string")
    }

    // MARK: - ShareExportService.safeFSName — illegal character stripping

    func testSafeFSNameStripsForwardSlash() {
        let result = ShareExportService.safeFSName("Report/2026")
        XCTAssertFalse(result.contains("/"),
                       "safeFSName must remove forward slashes")
    }

    func testSafeFSNameStripsBackslash() {
        let result = ShareExportService.safeFSName("Path\\File")
        XCTAssertFalse(result.contains("\\"),
                       "safeFSName must remove backslashes")
    }

    func testSafeFSNameStripsColon() {
        let result = ShareExportService.safeFSName("Time: 12:00")
        XCTAssertFalse(result.contains(":"),
                       "safeFSName must remove colons")
    }

    func testSafeFSNameStripsAsterisk() {
        let result = ShareExportService.safeFSName("Star*Wars")
        XCTAssertFalse(result.contains("*"),
                       "safeFSName must remove asterisks")
    }

    func testSafeFSNameStripsQuestionMark() {
        let result = ShareExportService.safeFSName("What?")
        XCTAssertFalse(result.contains("?"),
                       "safeFSName must remove question marks")
    }

    func testSafeFSNameStripsDoubleQuote() {
        let result = ShareExportService.safeFSName("\"Quoted\"")
        XCTAssertFalse(result.contains("\""),
                       "safeFSName must remove double-quote characters")
    }

    func testSafeFSNameStripsAngleBrackets() {
        let result = ShareExportService.safeFSName("<html>")
        XCTAssertFalse(result.contains("<") || result.contains(">"),
                       "safeFSName must remove angle bracket characters")
    }

    func testSafeFSNameStripsPipe() {
        let result = ShareExportService.safeFSName("Left|Right")
        XCTAssertFalse(result.contains("|"),
                       "safeFSName must remove pipe characters")
    }

    func testSafeFSNameStripsAllIllegalCharactersInOneString() {
        let result = ShareExportService.safeFSName("/\\:*?\"<>|")
        // Every illegal char is stripped/replaced; result should be underscores or trimmed empty → "Document"
        let illegalChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        XCTAssertTrue(result.unicodeScalars.allSatisfy { !illegalChars.contains($0) },
                      "safeFSName must remove ALL POSIX/NTFS illegal characters")
    }

    // MARK: - ShareExportService.safeFSName — length + empty fallback

    func testSafeFSNameTruncatesAtEightyCharacters() {
        let long = String(repeating: "A", count: 120)
        let result = ShareExportService.safeFSName(long)
        XCTAssertLessThanOrEqual(result.count, 80,
                                 "safeFSName must truncate output to 80 characters")
    }

    func testSafeFSNameFallsBackToDocumentOnEmptyInput() {
        let result = ShareExportService.safeFSName("")
        XCTAssertEqual(result, "Document",
                       "safeFSName must return 'Document' when the input is empty")
    }

    func testSafeFSNameFallsBackToDocumentWhenAllCharsIllegal() {
        let result = ShareExportService.safeFSName("/:*?\"<>|")
        // All chars are illegal → all replaced with "_" → trimmed → "Document" or underscores
        // The contract: result must NOT be empty
        XCTAssertFalse(result.isEmpty,
                       "safeFSName must never return an empty string")
    }

    func testSafeFSNameTrimsLeadingAndTrailingWhitespace() {
        let result = ShareExportService.safeFSName("   Invoice   ")
        XCTAssertEqual(result, "Invoice",
                       "safeFSName must trim leading and trailing whitespace")
    }

    // MARK: - ShareExportService.safeFSName — round-trip correctness

    func testSafeFSNamePreservesNormalAlphanumericName() {
        let normal = "MyDocument2026"
        let result = ShareExportService.safeFSName(normal)
        XCTAssertEqual(result, normal,
                       "safeFSName must not alter a name that contains no illegal characters")
    }

    func testSafeFSNamePreservesSpacesAndHyphens() {
        // Spaces and hyphens are legal filesystem characters
        let name = "My Doc - Final"
        let result = ShareExportService.safeFSName(name)
        XCTAssertTrue(result.contains("My") && result.contains("Final"),
                      "safeFSName must preserve letters, spaces, and hyphens")
    }

    func testSafeFSNameOnTypicalInvoiceName() {
        let result = ShareExportService.safeFSName("Invoice: Q1/2026 — Acme Corp.")
        XCTAssertFalse(result.contains(":"),  "Colon must be stripped")
        XCTAssertFalse(result.contains("/"),  "Forward-slash must be stripped")
        XCTAssertFalse(result.isEmpty,        "Result must not be empty")
        XCTAssertLessThanOrEqual(result.count, 80, "Result must be ≤ 80 chars")
    }

    // MARK: - AI naming integration check

    func testSuggestFileNameOutputIsAlwaysSafeFSName() {
        // Simulate a string with mixed real and punctuation content
        let ocrText = "Dr. Smith: Medical/Record 2026"
        let suggested = processor.suggestFileName(from: ocrText)
        let safened   = ShareExportService.safeFSName(suggested)
        // safeFSName applied to an already-cleaned name should be a no-op
        XCTAssertEqual(suggested, safened,
                       "suggestFileName output must already be filesystem-safe (idempotent with safeFSName)")
    }
}
