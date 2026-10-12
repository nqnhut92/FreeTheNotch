import Foundation

/// The Vietnamese lunisolar calendar (âm lịch), computed offline.
///
/// The rules are those of the traditional Chinese calendar, applied in
/// Vietnam's civil time (UTC+7):
/// - a month begins on the day of the new moon;
/// - the 11th month is the one that holds the December solstice;
/// - when 13 new moons separate two 11th months, the first month without a
///   principal solar term (the Sun crossing a multiple of 30° of longitude)
///   is the leap month and repeats the number of the month before it.
///
/// Apple's `.chinese` calendar applies the same rules in UTC+8, so a new moon
/// between 23:00 and midnight Hanoi time starts its month a day later there
/// (Tết 1985 and 2007, for example).
///
/// The astronomy follows Jean Meeus, *Astronomical Algorithms* (2nd ed.,
/// 1998): chapter 49 for new moons, chapter 25 for the Sun's apparent
/// longitude and chapter 27 for the solstice, with the Espenak–Meeus
/// polynomials for ΔT. That is accurate to a few minutes for 1900–2200, which
/// matters only when a new moon or a solar term falls minutes from midnight.
enum LunarCalendar {
    struct LunarDate: Equatable {
        let day: Int
        let month: Int
        let year: Int
        let isLeapMonth: Bool

        /// The sexagenary name of the lunar year, e.g. "Bính Ngọ".
        var yearName: String { LunarCalendar.canChi(year: year) }

        /// "1/9 năm Bính Ngọ", or "15/4 nhuận năm Ất Tỵ" in a leap month.
        var displayText: String {
            "\(day)/\(month)\(isLeapMonth ? " nhuận" : "") năm \(yearName)"
        }
    }

    /// The lunar date of the civil day that holds `date` in `calendar`.
    static func lunarDate(for date: Date, calendar: Calendar = .current) -> LunarDate {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return lunarDate(year: components.year ?? 2000, month: components.month ?? 1, day: components.day ?? 1)
    }

    /// The lunar date of a Gregorian calendar day.
    static func lunarDate(year: Int, month: Int, day: Int) -> LunarDate {
        let dayNumber = CivilDay.number(year: year, month: month, day: day)

        // The lunar year that runs from one 11th month to the next.
        var startYear = year
        var start = firstLunationOfMonth11(gregorianYear: year)
        if CivilDay.of(newMoonLunation: start) > dayNumber {
            startYear -= 1
            start = firstLunationOfMonth11(gregorianYear: startYear)
        }
        let monthCount = firstLunationOfMonth11(gregorianYear: startYear + 1) - start

        var index = Int(Double(dayNumber - CivilDay.of(newMoonLunation: start)) / Astronomy.synodicMonth)
        while index + 1 < monthCount, CivilDay.of(newMoonLunation: start + index + 1) <= dayNumber { index += 1 }
        while index > 0, CivilDay.of(newMoonLunation: start + index) > dayNumber { index -= 1 }

        let leapIndex = monthCount == 13 ? (1..<13).first { !hasPrincipalTerm(lunation: start + $0) } : nil
        let ordinal = index - (leapIndex.map { index >= $0 ? 1 : 0 } ?? 0)
        let unwrappedMonth = 11 + ordinal

        return LunarDate(
            day: dayNumber - CivilDay.of(newMoonLunation: start + index) + 1,
            month: unwrappedMonth > 12 ? unwrappedMonth - 12 : unwrappedMonth,
            year: unwrappedMonth > 12 ? startYear + 1 : startYear,
            isLeapMonth: index == leapIndex
        )
    }

    private static let heavenlyStems = ["Giáp", "Ất", "Bính", "Đinh", "Mậu", "Kỷ", "Canh", "Tân", "Nhâm", "Quý"]
    private static let earthlyBranches = [
        "Tý", "Sửu", "Dần", "Mão", "Thìn", "Tỵ", "Ngọ", "Mùi", "Thân", "Dậu", "Tuất", "Hợi",
    ]

    /// The sexagenary (Can Chi) name of a lunar year: 1984 is Giáp Tý.
    static func canChi(year: Int) -> String {
        let offset = year - 1984
        let stem = heavenlyStems[(offset % 10 + 10) % 10]
        let branch = earthlyBranches[(offset % 12 + 12) % 12]
        return "\(stem) \(branch)"
    }

    /// The lunation whose new moon starts the 11th month: the last new moon
    /// on or before the civil day of the December solstice.
    static func firstLunationOfMonth11(gregorianYear year: Int) -> Int {
        let solsticeDay = CivilDay.of(julianDay: Astronomy.universalTime(Astronomy.decemberSolstice(year: year)))
        var lunation = Astronomy.lunation(near: Double(solsticeDay))
        while CivilDay.of(newMoonLunation: lunation) > solsticeDay { lunation -= 1 }
        while CivilDay.of(newMoonLunation: lunation + 1) <= solsticeDay { lunation += 1 }
        return lunation
    }

    /// Whether the Sun crosses a multiple of 30° on one of the month's days,
    /// from the start of its first day to the start of the next month.
    static func hasPrincipalTerm(lunation: Int) -> Bool {
        func sector(atStartOf day: Int) -> Int {
            Int(
                Astronomy.apparentSolarLongitude(julianEphemerisDay: Astronomy.ephemerisTime(CivilDay.midnight(day)))
                    / 30)
        }
        return sector(atStartOf: CivilDay.of(newMoonLunation: lunation))
            != sector(atStartOf: CivilDay.of(newMoonLunation: lunation + 1))
    }
}

// MARK: - Civil days in Vietnam

extension LunarCalendar {
    /// Civil days in Vietnam, numbered like Julian Day Numbers: day N runs
    /// from Julian Day N − 0.5 to N + 0.5 in local time (UTC+7).
    enum CivilDay {
        static let utcOffsetInDays = 7.0 / 24

        private static let gregorianUTC: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            return calendar
        }()

        /// Julian Day Number at 1970-01-01.
        private static let unixEpochDayNumber = 2_440_588

        static func number(year: Int, month: Int, day: Int) -> Int {
            let components = DateComponents(year: year, month: month, day: day)
            let midnight = gregorianUTC.date(from: components) ?? Date(timeIntervalSince1970: 0)
            return unixEpochDayNumber + Int((midnight.timeIntervalSince1970 / 86_400).rounded(.down))
        }

        /// The civil day holding an instant given as a Julian Day in UT.
        static func of(julianDay: Double) -> Int {
            Int((julianDay + 0.5 + utcOffsetInDays).rounded(.down))
        }

        static func of(newMoonLunation lunation: Int) -> Int {
            of(julianDay: Astronomy.universalTime(Astronomy.newMoon(lunation: lunation)))
        }

        /// The start of a civil day, as a Julian Day in UT.
        static func midnight(_ day: Int) -> Double {
            Double(day) - 0.5 - utcOffsetInDays
        }
    }
}

// MARK: - Astronomy (Meeus)

extension LunarCalendar {
    /// Times are Julian Days: Julian Ephemeris Days (TT) where Meeus's series
    /// expect them, Universal Time for civil days.
    enum Astronomy {
        static let synodicMonth = 29.530588861

        private static func sinDegrees(_ degrees: Double) -> Double { sin(degrees * .pi / 180) }

        /// The lunation nearest an instant; lunation 0 is the new moon of
        /// 2000-01-06.
        static func lunation(near julianDay: Double) -> Int {
            Int(((julianDay - 2_451_550.09766) / synodicMonth).rounded())
        }

        /// Instant of the mean-corrected new moon of a lunation, in Julian
        /// Ephemeris Days (Meeus, chapter 49).
        static func newMoon(lunation: Int) -> Double {
            let k = Double(lunation)
            let t = k / 1236.85
            let t2 = t * t
            let t3 = t2 * t
            let t4 = t3 * t

            let meanPhase = 2_451_550.09766 + synodicMonth * k + 0.00015437 * t2 - 0.000000150 * t3 + 0.00000000073 * t4
            let e = 1 - 0.002516 * t - 0.0000074 * t2
            let sunAnomaly = 2.5534 + 29.10535670 * k - 0.0000014 * t2 - 0.00000011 * t3
            let moonAnomaly = 201.5643 + 385.81693528 * k + 0.0107582 * t2 + 0.00001238 * t3 - 0.000000058 * t4
            let latitude = 160.7108 + 390.67050284 * k - 0.0016118 * t2 - 0.00000227 * t3 + 0.000000011 * t4
            let node = 124.7746 - 1.56375588 * k + 0.0020672 * t2 + 0.00000215 * t3

            let (m, mp, f) = (sunAnomaly, moonAnomaly, latitude)
            let periodicTerms: [(coefficient: Double, argument: Double)] = [
                (-0.40720, mp),
                (0.17241 * e, m),
                (0.01608, 2 * mp),
                (0.01039, 2 * f),
                (0.00739 * e, mp - m),
                (-0.00514 * e, mp + m),
                (0.00208 * e * e, 2 * m),
                (-0.00111, mp - 2 * f),
                (-0.00057, mp + 2 * f),
                (0.00056 * e, 2 * mp + m),
                (-0.00042, 3 * mp),
                (0.00042 * e, m + 2 * f),
                (0.00038 * e, m - 2 * f),
                (-0.00024 * e, 2 * mp - m),
                (-0.00017, node),
                (-0.00007, mp + 2 * m),
                (0.00004, 2 * mp - 2 * f),
                (0.00004, 3 * m),
                (0.00003, mp + m - 2 * f),
                (0.00003, 2 * mp + 2 * f),
                (-0.00003, mp + m + 2 * f),
                (0.00003, mp - m + 2 * f),
                (-0.00002, mp - m - 2 * f),
                (-0.00002, 3 * mp + m),
                (0.00002, 4 * mp),
            ]
            let planetaryTerms: [(coefficient: Double, argument: Double)] = [
                (0.000325, 299.77 + 0.107408 * k - 0.009173 * t2),
                (0.000165, 251.88 + 0.016321 * k),
                (0.000164, 251.83 + 26.651886 * k),
                (0.000126, 349.42 + 36.412478 * k),
                (0.000110, 84.66 + 18.206239 * k),
                (0.000062, 141.74 + 53.303771 * k),
                (0.000060, 207.14 + 2.453732 * k),
                (0.000056, 154.84 + 7.306860 * k),
                (0.000047, 34.52 + 27.261239 * k),
                (0.000042, 207.19 + 0.121824 * k),
                (0.000040, 291.34 + 1.844379 * k),
                (0.000037, 161.72 + 24.198154 * k),
                (0.000035, 239.56 + 25.513099 * k),
                (0.000023, 331.55 + 3.592518 * k),
            ]
            let corrections = (periodicTerms + planetaryTerms).reduce(0) {
                $0 + $1.coefficient * sinDegrees($1.argument)
            }
            return meanPhase + corrections
        }

        /// The Sun's apparent longitude in degrees, 0 ..< 360 (Meeus,
        /// chapter 25, low accuracy: about 0.01°).
        static func apparentSolarLongitude(julianEphemerisDay jde: Double) -> Double {
            let t = (jde - 2_451_545) / 36_525
            let meanLongitude = 280.46646 + 36_000.76983 * t + 0.0003032 * t * t
            let meanAnomaly = 357.52911 + 35_999.05029 * t - 0.0001537 * t * t
            let center =
                (1.914602 - 0.004817 * t - 0.000014 * t * t) * sinDegrees(meanAnomaly)
                + (0.019993 - 0.000101 * t) * sinDegrees(2 * meanAnomaly)
                + 0.000289 * sinDegrees(3 * meanAnomaly)
            let node = 125.04 - 1_934.136 * t
            let longitude = meanLongitude + center - 0.00569 - 0.00478 * sinDegrees(node)
            let normalized = longitude.truncatingRemainder(dividingBy: 360)
            return normalized < 0 ? normalized + 360 : normalized
        }

        /// The December solstice of a year, in Julian Ephemeris Days, found
        /// by Meeus's correction step (chapter 27) from December 21.
        static func decemberSolstice(year: Int) -> Double {
            var jde = Double(CivilDay.number(year: year, month: 12, day: 21))
            for _ in 0..<10 {
                let step = 58 * sinDegrees(270 - apparentSolarLongitude(julianEphemerisDay: jde))
                jde += step
                if abs(step) < 1e-6 { break }
            }
            return jde
        }

        static func universalTime(_ jde: Double) -> Double {
            jde - deltaT(julianDay: jde) / 86_400
        }

        static func ephemerisTime(_ julianDay: Double) -> Double {
            julianDay + deltaT(julianDay: julianDay) / 86_400
        }

        /// TT − UT in seconds (Espenak and Meeus, NASA Five Millennium Canon
        /// of Solar Eclipses, 2006).
        static func deltaT(julianDay: Double) -> Double {
            let y = 2000 + (julianDay - 2_451_545) / 365.25
            switch y {
            case ..<1900:
                let u = (y - 1820) / 100
                return -20 + 32 * u * u
            case ..<1920:
                let t = y - 1900
                return -2.79 + 1.494119 * t - 0.0598939 * t * t + 0.0061966 * t * t * t - 0.000197 * t * t * t * t
            case ..<1941:
                let t = y - 1920
                return 21.20 + 0.84493 * t - 0.076100 * t * t + 0.0020936 * t * t * t
            case ..<1961:
                let t = y - 1950
                return 29.07 + 0.407 * t - t * t / 233 + t * t * t / 2547
            case ..<1986:
                let t = y - 1975
                return 45.45 + 1.067 * t - t * t / 260 - t * t * t / 718
            case ..<2005:
                let t = y - 2000
                return 63.86 + 0.3345 * t - 0.060374 * t * t + 0.0017275 * pow(t, 3) + 0.000651814 * pow(t, 4)
                    + 0.00002373599 * pow(t, 5)
            case ..<2050:
                let t = y - 2000
                return 62.92 + 0.32217 * t + 0.005589 * t * t
            case ..<2150:
                let u = (y - 1820) / 100
                return -20 + 32 * u * u - 0.5628 * (2150 - y)
            default:
                let u = (y - 1820) / 100
                return -20 + 32 * u * u
            }
        }
    }
}
