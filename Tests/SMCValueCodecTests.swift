import Foundation
import Testing

struct SMCValueCodecTests {
    @Test(arguments: [
        // flt: little-endian IEEE 754 single; 42.5 is 0x422A0000.
        ([0x00, 0x00, 0x2A, 0x42] as [UInt8], "flt ", 42.5),
        // sp78: big-endian signed 8.8 fixed point.
        ([0x28, 0x80], "sp78", 40.5),
        ([0xFF, 0x80], "sp78", -0.5),
        // fpe2: big-endian unsigned 14.2 fixed point; 0x0190 = 400.
        ([0x01, 0x90], "fpe2", 100),
        ([0x2A], "ui8 ", 42),
        ([0x01, 0x02], "ui16", 258),
        ([0x00, 0x00, 0x01, 0x00], "ui32", 256),
        // ioft: little-endian unsigned 48.16 fixed point.
        ([0x00, 0x80, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00], "ioft", 3.5),
    ])
    func decodes(_ bytes: [UInt8], type: String, expected: Double) {
        #expect(SMCValueCodec.decode(bytes, type: type) == expected)
    }

    @Test(arguments: [
        ([0x28, 0x80, 0x00] as [UInt8], "sp78"),
        ([0x00, 0x00], "flt "),
        ([0x01], "ui16"),
        ([0x01, 0x02, 0x03, 0x04], "ioft"),
        ([0x2A], "ch8*"),
        ([], "ui8 "),
    ])
    func rejectsWrongSizeOrUnknownType(_ bytes: [UInt8], type: String) {
        #expect(SMCValueCodec.decode(bytes, type: type) == nil)
    }

    @Test func rejectsNonFiniteFloat() {
        // 0x7FC00000 is a quiet NaN.
        #expect(SMCValueCodec.decode([0x00, 0x00, 0xC0, 0x7F], type: "flt ") == nil)
    }
}
