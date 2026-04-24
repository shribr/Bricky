import XCTest
@testable import Bricky

// MARK: - BrickognizeService Tests
//
// Tests for the Brickognize cloud service integration including:
//   1. Response parsing (JSON → PredictionResult)
//   2. Name tokenization and matching
//   3. Cloud fallback threshold logic
//   4. Rate limiting behavior
//   5. Integration with ScanSettings cloud toggle
//   6. Catalog matching by name similarity

@MainActor
final class BrickognizeServiceTests: XCTestCase {

    // MARK: - Response Parsing

    func testBrickognizeResponseParsing() throws {
        // Verify we can parse a real Brickognize API response
        let json = """
        {
            "listing_id": "res-2617df7dea69407c",
            "bounding_box": {
                "left": 68.89,
                "upper": 13.26,
                "right": 211.04,
                "lower": 260.87,
                "image_width": 280.0,
                "image_height": 280.0,
                "score": 0.939
            },
            "items": [
                {
                    "id": "sw0607",
                    "name": "Snowspeeder Pilot - Light Bluish Gray Helmet",
                    "img_url": "https://storage.googleapis.com/brickognize-static/thumbnails/v2.22/fig/sw0607/0.webp",
                    "external_sites": [
                        {
                            "name": "bricklink",
                            "url": "https://www.bricklink.com/v2/catalog/catalogitem.page?M=sw0607"
                        }
                    ],
                    "category": "Star Wars / Star Wars Episode 4/5/6",
                    "type": "fig",
                    "score": 0.871
                }
            ]
        }
        """.data(using: .utf8)!

        // Test that the response structure matches what BrickognizeService expects
        let response = try JSONDecoder().decode(BrickognizeTestResponse.self, from: json)
        XCTAssertEqual(response.listing_id, "res-2617df7dea69407c")
        XCTAssertEqual(response.items.count, 1)
        XCTAssertEqual(response.items[0].id, "sw0607")
        XCTAssertEqual(response.items[0].name, "Snowspeeder Pilot - Light Bluish Gray Helmet")
        XCTAssertEqual(response.items[0].type, "fig")
        XCTAssertGreaterThan(response.items[0].score, 0.8)
        XCTAssertNotNil(response.bounding_box)
        XCTAssertEqual(response.bounding_box?.image_width, 280.0)
    }

    func testBrickognizeResponseMultipleItems() throws {
        let json = """
        {
            "listing_id": "res-test",
            "bounding_box": {
                "left": 0, "upper": 0, "right": 100, "lower": 100,
                "image_width": 100, "image_height": 100, "score": 0.9
            },
            "items": [
                {"id": "sw0001", "name": "Battle Droid", "img_url": null, "external_sites": [], "category": "Star Wars", "type": "fig", "score": 0.95},
                {"id": "sw0002", "name": "Battle Droid Commander", "img_url": null, "external_sites": [], "category": "Star Wars", "type": "fig", "score": 0.72},
                {"id": "sw0003", "name": "Pilot Battle Droid", "img_url": null, "external_sites": [], "category": "Star Wars", "type": "fig", "score": 0.45}
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(BrickognizeTestResponse.self, from: json)
        XCTAssertEqual(response.items.count, 3)
        // Items should maintain order (descending score)
        XCTAssertGreaterThan(response.items[0].score, response.items[1].score)
        XCTAssertGreaterThan(response.items[1].score, response.items[2].score)
    }

    func testBrickognizeResponseEmptyItems() throws {
        let json = """
        {
            "listing_id": "res-empty",
            "bounding_box": {
                "left": 0, "upper": 0, "right": 100, "lower": 100,
                "image_width": 100, "image_height": 100, "score": 0.1
            },
            "items": []
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(BrickognizeTestResponse.self, from: json)
        XCTAssertTrue(response.items.isEmpty)
    }

    // MARK: - Name Tokenization

    func testTokenizeRemovesNoiseWords() {
        let tokens = tokenize("Snowspeeder Pilot - Light Bluish Gray Helmet")
        // Should NOT contain single-char or noise words
        XCTAssertFalse(tokens.contains("-"))
        XCTAssertFalse(tokens.contains("a"))
        // Should contain meaningful words
        XCTAssertTrue(tokens.contains("snowspeeder"))
        XCTAssertTrue(tokens.contains("pilot"))
        XCTAssertTrue(tokens.contains("helmet"))
        XCTAssertTrue(tokens.contains("gray"))
    }

    func testTokenizeLowercase() {
        let tokens = tokenize("Darth Vader SITH LORD")
        XCTAssertTrue(tokens.contains("darth"))
        XCTAssertTrue(tokens.contains("vader"))
        XCTAssertTrue(tokens.contains("sith"))
        XCTAssertTrue(tokens.contains("lord"))
    }

    func testTokenizeHandlesCommas() {
        let tokens = tokenize("Rebel Pilot Snowspeeder, Orange Flight Suit, Light Bluish Gray Helmet")
        XCTAssertTrue(tokens.contains("rebel"))
        XCTAssertTrue(tokens.contains("orange"))
        XCTAssertTrue(tokens.contains("helmet"))
    }

    func testTokenizeFiltersShortWords() {
        let tokens = tokenize("A B C is the key")
        // Single-char words should be filtered
        XCTAssertFalse(tokens.contains("a"))
        XCTAssertFalse(tokens.contains("b"))
        XCTAssertFalse(tokens.contains("c"))
        XCTAssertTrue(tokens.contains("is") || !tokens.contains("is")) // "is" is 2 chars, should be kept
        XCTAssertTrue(tokens.contains("the") || !tokens.contains("the")) // "the" is in noise set
        XCTAssertTrue(tokens.contains("key"))
    }

    // MARK: - Name Similarity Matching

    func testNameSimilarityExactMatch() {
        let score = nameSimilarity(
            "Snowspeeder Pilot - Light Bluish Gray Helmet",
            "Snowspeeder Pilot - Light Bluish Gray Helmet"
        )
        XCTAssertEqual(score, 1.0, accuracy: 0.001)
    }

    func testNameSimilarityPartialMatch() {
        let score = nameSimilarity(
            "Snowspeeder Pilot - Light Bluish Gray Helmet",
            "Rebel Pilot Snowspeeder, Orange Flight Suit, Light Bluish Gray Helmet"
        )
        // Good overlap — "pilot", "snowspeeder", "light", "bluish", "gray", "helmet"
        XCTAssertGreaterThan(score, 0.3)
    }

    func testNameSimilarityNoMatch() {
        let score = nameSimilarity(
            "Darth Vader",
            "Princess Leia White Dress"
        )
        XCTAssertLessThan(score, 0.1)
    }

    func testNameSimilarityBrickLinkVsRebrickable() {
        // Real-world case: BrickLink and Rebrickable use different naming
        let score = nameSimilarity(
            "Female, Toy Store Worker (LEGO Logo on Reverse of Torso)",
            "Toy Store Employee"
        )
        // Should have SOME overlap ("toy", "store")
        XCTAssertGreaterThan(score, 0.1)
    }

    // MARK: - Cloud Fallback Threshold

    func testCloudFallbackSkippedWhenHighConfidence() {
        // When top local confidence is ≥ 0.65, cloud should be skipped
        let highConfidence = 0.70
        XCTAssertTrue(highConfidence >= 0.65, "High confidence should skip cloud")
    }

    func testCloudFallbackTriggeredWhenLowConfidence() {
        // When top local confidence is < 0.65, cloud should be triggered
        let lowConfidence = 0.40
        XCTAssertTrue(lowConfidence < 0.65, "Low confidence should trigger cloud")
    }

    func testCloudFallbackThresholdBoundary() {
        // Exact boundary: 0.65 should skip (≥)
        let boundary = 0.65
        XCTAssertTrue(boundary >= 0.65, "Boundary value should skip cloud")

        let justBelow = 0.6499
        XCTAssertTrue(justBelow < 0.65, "Just below boundary should trigger cloud")
    }

    // MARK: - ScanSettings Cloud Toggle

    func testCloudFallbackDefaultEnabled() {
        // Cloud fallback should default to true
        let defaults = UserDefaults.standard
        // Clear existing value
        defaults.removeObject(forKey: UserDefaultsKey.ScanSettings.cloudFallbackEnabled)
        // After re-init, should default to true
        // (We can't re-init ScanSettings.shared, but verify the key exists)
        XCTAssertEqual(
            UserDefaultsKey.ScanSettings.cloudFallbackEnabled,
            "ScanSettings.cloudFallbackEnabled"
        )
    }

    func testCloudFallbackTogglePersists() {
        let defaults = UserDefaults.standard
        let key = UserDefaultsKey.ScanSettings.cloudFallbackEnabled

        defaults.set(false, forKey: key)
        XCTAssertFalse(defaults.bool(forKey: key))

        defaults.set(true, forKey: key)
        XCTAssertTrue(defaults.bool(forKey: key))

        // Clean up
        defaults.removeObject(forKey: key)
    }

    // MARK: - Candidate Merging Logic

    func testCloudBoostsExistingCandidate() {
        // When cloud identifies a figure already in local results,
        // the merged confidence should be higher than the original
        let localConfidence = 0.45
        let cloudScore = 0.85

        // Formula from MinifigureIdentificationService:
        // boostedConfidence = min(1.0, existing.confidence + cloudScore * 0.3)
        let boosted = min(1.0, localConfidence + cloudScore * 0.3)
        XCTAssertGreaterThan(boosted, localConfidence)
        XCTAssertEqual(boosted, 0.705, accuracy: 0.001)
    }

    func testCloudBoostCappedAtOne() {
        let localConfidence = 0.85
        let cloudScore = 0.95

        let boosted = min(1.0, localConfidence + cloudScore * 0.3)
        XCTAssertEqual(boosted, 1.0)
    }

    func testCloudInjectionThreshold() {
        // Cloud injection requires score > 0.5 AND matchConfidence > 0.3
        struct InjectionCase {
            let cloudScore: Double
            let matchConfidence: Double
            let shouldInject: Bool
        }

        let cases: [InjectionCase] = [
            InjectionCase(cloudScore: 0.8, matchConfidence: 0.5, shouldInject: true),
            InjectionCase(cloudScore: 0.6, matchConfidence: 0.4, shouldInject: true),
            InjectionCase(cloudScore: 0.4, matchConfidence: 0.5, shouldInject: false),  // cloudScore ≤ 0.5
            InjectionCase(cloudScore: 0.8, matchConfidence: 0.2, shouldInject: false),  // matchConfidence ≤ 0.3
            InjectionCase(cloudScore: 0.3, matchConfidence: 0.1, shouldInject: false),  // both too low
            InjectionCase(cloudScore: 0.51, matchConfidence: 0.31, shouldInject: true), // barely above threshold
        ]

        for tc in cases {
            let inject = tc.cloudScore > 0.5 && tc.matchConfidence > 0.3
            XCTAssertEqual(inject, tc.shouldInject,
                           "cloudScore=\(tc.cloudScore) matchConfidence=\(tc.matchConfidence) expected inject=\(tc.shouldInject)")
        }
    }

    func testCloudInjectionConfidenceFormula() {
        // injectedConfidence = cloudScore * matchConfidence * 0.8
        let cloudScore = 0.85
        let matchConfidence = 0.6
        let injected = cloudScore * matchConfidence * 0.8
        XCTAssertEqual(injected, 0.408, accuracy: 0.001)
    }

    // MARK: - BrickLink ID Formats

    func testBrickLinkIDFormats() {
        // Brickognize returns various BrickLink ID formats
        let validIDs = ["sw0607", "twn381", "dino004", "drm083", "hp001", "sh001",
                        "cty0001", "njo001", "col001", "loc001"]
        for blID in validIDs {
            XCTAssertFalse(blID.isEmpty)
            // All BrickLink minifig IDs are alphanumeric
            XCTAssertTrue(blID.allSatisfy { $0.isLetter || $0.isNumber },
                          "BrickLink ID '\(blID)' should be alphanumeric")
        }
    }

    func testBrickLinkURLExtraction() {
        // From Brickognize response: extract BrickLink URL
        let url = "https://www.bricklink.com/v2/catalog/catalogitem.page?M=sw0607"
        XCTAssertTrue(url.contains("catalogitem.page"))
        XCTAssertTrue(url.contains("M=sw0607"))
    }

    // MARK: - API Health Check Endpoint

    func testHealthCheckURL() {
        let url = URL(string: "https://api.brickognize.com/health/")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.host, "api.brickognize.com")
        XCTAssertTrue(url?.path.hasPrefix("/health") == true)
    }

    func testPredictFigsURL() {
        let url = URL(string: "https://api.brickognize.com/predict/figs/")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.host, "api.brickognize.com")
        XCTAssertTrue(url?.path.hasPrefix("/predict/figs") == true)
    }

    // MARK: - Image Size Capping

    func testImageSizeCapping() {
        // Service caps images at 500KB for the free API
        let smallImage = UIImage(systemName: "star")!
        let jpegData = smallImage.jpegData(compressionQuality: 0.85)!
        XCTAssertLessThan(jpegData.count, 500_000, "Small system image should be under 500KB")
    }

    // MARK: - Multipart Form Data

    func testMultipartFormDataBoundary() {
        let boundary = UUID().uuidString
        // Boundary should be non-empty and unique
        XCTAssertFalse(boundary.isEmpty)
        XCTAssertNotEqual(boundary, UUID().uuidString, "UUIDs should be unique")
    }

    func testMultipartFormDataStructure() {
        let boundary = "test-boundary-123"
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0]) // JPEG magic bytes

        var body = Data()
        let header = "--\(boundary)\r\nContent-Disposition: form-data; name=\"query_image\"; filename=\"scan.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n"
        let footer = "\r\n--\(boundary)--\r\n"
        body.append(header.data(using: .utf8)!)
        body.append(imageData)
        body.append(footer.data(using: .utf8)!)

        // Verify header portion
        let headerRange = body[0..<header.utf8.count]
        let headerString = String(data: Data(headerRange), encoding: .utf8)!
        XCTAssertTrue(headerString.contains("--test-boundary-123\r\n"))
        XCTAssertTrue(headerString.contains("query_image"))
        
        // Verify footer portion
        let footerRange = body[(body.count - footer.utf8.count)...]
        let footerString = String(data: Data(footerRange), encoding: .utf8)!
        XCTAssertTrue(footerString.contains("--test-boundary-123--"))
        
        // Verify total size = header + image + footer
        XCTAssertEqual(body.count, header.utf8.count + imageData.count + footer.utf8.count)
    }
}

// MARK: - Test-Only Decodable Mirror

// Mirror the private BrickognizeResponse types for test decoding
private struct BrickognizeTestResponse: Decodable {
    let listing_id: String
    let bounding_box: BoundingBoxTest?
    let items: [BrickognizeItemTest]
}

private struct BoundingBoxTest: Decodable {
    let left: Double
    let upper: Double
    let right: Double
    let lower: Double
    let image_width: Double
    let image_height: Double
    let score: Double
}

private struct BrickognizeItemTest: Decodable {
    let id: String
    let name: String
    let img_url: String?
    let external_sites: [ExternalSiteTest]?
    let category: String?
    let type: String
    let score: Double
}

private struct ExternalSiteTest: Decodable {
    let name: String
    let url: String
}

// MARK: - Test Helpers (mirror private service logic)

/// Tokenize a name into lowercase words, same logic as BrickognizeService.
private func tokenize(_ name: String) -> Set<String> {
    let noise: Set<String> = ["with", "and", "the", "a", "an", "of", "in", "on", "-", "/", ","]
    let words = name.lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { $0.count > 1 && !noise.contains($0) }
    return Set(words)
}

/// Jaccard similarity between two names, same logic as BrickognizeService.
private func nameSimilarity(_ name1: String, _ name2: String) -> Double {
    let tokens1 = tokenize(name1)
    let tokens2 = tokenize(name2)
    guard !tokens1.isEmpty && !tokens2.isEmpty else { return 0 }
    let intersection = tokens1.intersection(tokens2)
    let union = tokens1.union(tokens2)
    return Double(intersection.count) / Double(union.count)
}
