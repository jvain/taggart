import Testing
@testable import TaggartCore

@Suite("Case conversion")
struct CaseConversionTests {
    func title(_ text: String) -> String { CaseConverter(.titleCase).convert(text) }
    func sentence(_ text: String) -> String { CaseConverter(.sentenceCase).convert(text) }

    @Test func titleCaseKeepsSmallWordsLowercase() {
        #expect(title("dancing in the dark") == "Dancing in the Dark")
        #expect(title("A DAY IN THE LIFE") == "A Day in the Life")
        #expect(title("to be or not to be") == "To Be or Not to Be")
        // First and last words, and those starting or ending a part, are capitalized.
        #expect(title("what it's made of (remix)") == "What It's Made Of (Remix)")
        #expect(title("the end: a new beginning") == "The End: A New Beginning")
        #expect(title("song for you - live at home") == "Song for You - Live at Home")
        #expect(title("(live at the house of blues)") == "(Live at the House of Blues)")
        #expect(title("rock 'n' roll") == "Rock 'n' Roll")
        #expect(title("song feat. other artist") == "Song feat. Other Artist")
        #expect(title("up-to-date") == "Up-to-Date")
    }

    @Test func titleCaseHandlesSpecialWords() {
        #expect(title("don't stop (live version)") == "Don't Stop (Live Version)")
        #expect(title("hip-hop/r&b") == "Hip-Hop/R&B")
        #expect(title("the 2nd time") == "The 2nd Time")
        #expect(title("'til the 90s") == "'Til the 90s")
        #expect(title("ääni ja öljy") == "Ääni Ja Öljy")
        #expect(title("r.e.m. [remastered]") == "R.E.M. [Remastered]")
        #expect(title("symphony no. 9, part iv") == "Symphony No. 9, Part IV")
        #expect(title("MIX VOL. II") == "Mix Vol. II")
        #expect(title("\"heroes\"") == "\"Heroes\"")
    }

    @Test func titleCaseKeepsCapitalsInNormalCaseText() {
        #expect(title("live at the BBC") == "Live at the BBC")
        #expect(title("McCartney's iPhone song") == "McCartney's iPhone Song")
        #expect(title("walk this way (feat. RUN-DMC)") == "Walk This Way (feat. RUN-DMC)")
        // Small words are small even in capitals.
        #expect(title("Best OF the Rest") == "Best of the Rest")
        // Text in capitals has no such hints: it's rewritten, using the words to keep.
        #expect(title("LIVE AT THE BBC") == "Live at the BBC")
        #expect(title("DJ SHADOW - ENDTRODUCING") == "DJ Shadow - Endtroducing")
        #expect(title("HELLO (LIVE)") == "Hello (Live)")
    }

    @Test func keptWordsCanBeChanged() {
        let converter = CaseConverter(.titleCase, keeping: ["ABBA", "feat."])
        #expect(converter.convert("THE BEST OF ABBA FEAT. BBC") == "The Best of ABBA feat. Bbc")
        #expect(CaseConverter(.titleCase, keeping: []).convert("ac/dc") == "Ac/Dc")
    }

    @Test func sentenceCase() {
        #expect(sentence("THE SONG OF THE YEAR") == "The song of the year")
        #expect(sentence("(intro) PART ONE") == "(Intro) part one")
        #expect(sentence("When I Grow Up") == "When I grow up")
        #expect(sentence("Live At The BBC") == "Live at the BBC")
        #expect(sentence("1999 Was A Year") == "1999 was a year")
    }

    @Test func otherStyles() {
        #expect(CaseConverter(.capitalizeEveryWord).convert("dancing in the dark") == "Dancing In The Dark")
        #expect(CaseConverter(.capitalizeEveryWord).convert("live at the bbc") == "Live At The BBC")
        #expect(CaseConverter(.uppercase).convert("Ääni") == "ÄÄNI")
        #expect(CaseConverter(.lowercase).convert("ÄÄNI dj") == "ääni dj")
    }

    @Test func keepsSpacingAndEmptyText() {
        #expect(title("  two  spaces\tand tab ") == "  Two  Spaces\tand Tab ")
        #expect(title("") == "")
        #expect(title("- (") == "- (")
    }
}
