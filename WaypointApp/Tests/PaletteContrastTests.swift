import XCTest
import SwiftUI
@testable import Waypoint

/// Paper mode's one real risk, measured.
///
/// "Easy on the eye" and "legible" pull against each other, and the usual way a reading mode
/// goes wrong is winning the first by quietly losing the second. The whole premise here is that
/// the strain comes from the white ground and the glow rather than from contrast — so paper can
/// warm the page and still clear the 4.5:1 that normal text needs. That premise is only worth
/// anything if something checks it.
@MainActor
final class PaletteContrastTests: XCTestCase {
    override func tearDown() {
        Palette.current = .standard
        super.tearDown()
    }

    /// WCAG 2.1 relative luminance.
    private func luminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ c: CGFloat) -> CGFloat {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    private func ratio(_ a: UIColor, _ b: UIColor) -> CGFloat {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func resolved(_ color: Color, dark: Bool) -> UIColor {
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
    }

    private func assertReadable(
        _ ink: Color, on ground: Color, dark: Bool, _ label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let measured = ratio(resolved(ink, dark: dark), resolved(ground, dark: dark))
        XCTAssertGreaterThanOrEqual(
            measured, 4.5,
            "\(label) measures \(String(format: "%.2f", measured)):1 — normal text needs 4.5:1",
            file: file, line: line
        )
    }

    /// Every ink the app puts on a card or a page, in both palettes and both schemes.
    func testEveryTextTokenIsReadableOnEveryGroundInBothPalettes() {
        for palette in Palette.allCases {
            Palette.current = palette
            for dark in [false, true] {
                let where_ = "\(palette.rawValue)/\(dark ? "dark" : "light")"
                for (name, ink) in [
                    ("textPrimary", ColorTokens.textPrimary),
                    ("textSecondary", ColorTokens.textSecondary),
                    ("textMuted", ColorTokens.textMuted),
                    ("textWarning", ColorTokens.textWarning),
                    ("textInProgress", ColorTokens.textInProgress)
                ] {
                    assertReadable(ink, on: ColorTokens.surface1, dark: dark, "\(where_) \(name) on card")
                    assertReadable(ink, on: ColorTokens.surface0, dark: dark, "\(where_) \(name) on page")
                }
            }
        }
    }

    /// The accent *is* the ink in paper, so it has to read as text as well as fill.
    func testThePaperAccentIsReadableAsInk() {
        Palette.current = .paper
        for dark in [false, true] {
            assertReadable(AccentSwatch.teal.markColor, on: ColorTokens.surface1, dark: dark, "paper accent on card")
        }
    }

    /// How far a colour sits from grey. Paper's ground carries a touch of warmth so it reads as
    /// paper rather than as a monitor, but nothing in it is allowed an actual hue.
    private func chroma(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return max(r, g, b) - min(r, g, b)
    }

    /// The test that would have caught the first attempt.
    ///
    /// That version was a sepia accent on a cream ground — warm, flat, and still unmistakably a
    /// colour scheme. It passed every contrast check here and was wrong anyway, because nothing
    /// asserted the thing the mode is actually *for*. Paper is monochrome; this says so in a way
    /// that fails if someone reaches for a hue again.
    func testNothingInPaperHasAHue() {
        Palette.current = .paper
        let tokens: [(String, Color)] = [
            ("surface0", ColorTokens.surface0), ("surface1", ColorTokens.surface1),
            ("textPrimary", ColorTokens.textPrimary), ("textSecondary", ColorTokens.textSecondary),
            ("textMuted", ColorTokens.textMuted), ("border", ColorTokens.border),
            ("warning", ColorTokens.warning), ("textWarning", ColorTokens.textWarning),
            ("inProgress", ColorTokens.inProgress), ("success", ColorTokens.success),
            ("priorityMedium", ColorTokens.priorityMedium)
        ]
        for dark in [false, true] {
            for (name, color) in tokens {
                let measured = chroma(resolved(color, dark: dark))
                XCTAssertLessThanOrEqual(
                    measured, 0.07,
                    "\(name) carries a hue (chroma \(String(format: "%.3f", measured))) — paper is monochrome"
                )
            }
            for swatch in AccentSwatch.allCases {
                XCTAssertLessThanOrEqual(chroma(resolved(swatch.color, dark: dark)), 0.07,
                                         "\(swatch.rawValue) still shows through in paper")
            }
        }
    }

    /// Paper is one appearance, not two. Every token has to resolve identically whichever scheme
    /// the device is in, or the light/dark control would quietly still be doing something.
    func testPaperLooksIdenticalInLightAndDark() {
        Palette.current = .paper
        for (name, color) in [
            ("surface0", ColorTokens.surface0), ("surface1", ColorTokens.surface1),
            ("textPrimary", ColorTokens.textPrimary), ("textMuted", ColorTokens.textMuted),
            ("border", ColorTokens.border), ("warning", ColorTokens.warning)
        ] {
            XCTAssertEqual(resolved(color, dark: false), resolved(color, dark: true),
                           "\(name) differs between schemes — paper has no light and dark")
        }
        XCTAssertEqual(Palette.paper.forcedColorScheme, .light)
        XCTAssertNil(Palette.standard.forcedColorScheme)
    }

    /// What paper actually trades, now that it's monochrome.
    ///
    /// This test used to assert paper was *softer* than standard, which was the first attempt's
    /// premise and is simply false of the finished thing: near-black on off-white measures about
    /// 16:1 against standard light's 14:1. Monochrome is a higher-contrast look, not a lower one.
    ///
    /// What survives is the half that was always the real point — the **ground**. Pure white at
    /// full brightness is the glare; an off-white page is dimmer whatever the ink on it does.
    func testPaperDimsTheGroundEvenThoughTheInkGetsDarker() {
        Palette.current = .standard
        let standardCard = luminance(resolved(ColorTokens.surface1, dark: false))
        Palette.current = .paper
        let paperCard = luminance(resolved(ColorTokens.surface1, dark: false))

        XCTAssertLessThan(paperCard, standardCard, "the page should emit less light than pure white")
        XCTAssertGreaterThan(paperCard, 0.8, "but still be a page, not a grey card")
    }

    /// Paper is matte. Every shadow in the app resolves through these three tokens, so this is
    /// the whole of the claim.
    func testPaperDrawsNoShadows() {
        Palette.current = .paper
        for (name, shadow) in [
            ("resting", ColorTokens.shadowResting),
            ("raised", ColorTokens.shadowRaised),
            ("floating", ColorTokens.shadowFloating)
        ] {
            var alpha: CGFloat = 0
            UIColor(shadow).getRed(nil, green: nil, blue: nil, alpha: &alpha)
            XCTAssertEqual(alpha, 0, "\(name) shadow should be clear in paper mode")
        }
        XCTAssertFalse(Palette.paper.usesDepth)
        XCTAssertTrue(Palette.standard.usesDepth)
    }

    /// Paper never uses pure white or pure black — the two values that do most of the glaring.
    func testPaperGroundsAreNeverPureWhiteOrBlack() {
        Palette.current = .paper
        for dark in [false, true] {
            for ground in [ColorTokens.surface0, ColorTokens.surface1] {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                resolved(ground, dark: dark).getRed(&r, green: &g, blue: &b, alpha: &a)
                XCTAssertFalse(r == 1 && g == 1 && b == 1, "paper should never be pure white")
                XCTAssertFalse(r == 0 && g == 0 && b == 0, "paper should never be pure black")
                // Warm: more red than blue, on both grounds, in both schemes.
                XCTAssertGreaterThan(r, b, "paper grounds should be warm")
            }
        }
    }

    /// Switching back has to actually switch back — the tokens are computed, and a cached
    /// `static let` slipping in anywhere would strand the app in whichever palette loaded first.
    func testTokensFollowThePaletteBackAndForth() {
        Palette.current = .standard
        let standardCard = resolved(ColorTokens.surface1, dark: false)
        Palette.current = .paper
        let paperCard = resolved(ColorTokens.surface1, dark: false)
        Palette.current = .standard
        let backAgain = resolved(ColorTokens.surface1, dark: false)

        XCTAssertNotEqual(standardCard, paperCard)
        XCTAssertEqual(standardCard, backAgain)
    }
}
