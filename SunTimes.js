.pragma library

// Ported verbatim from OmaShuffle's SunTimes.js (same author, MIT).

// Sun-position math for OmaShuffle's Day & Night mode. Pure logic, no QML or
// I/O - same rule as ThemeDeck.js, so it can be reasoned about (and
// node --check'd) on its own.
//
// Implements the standard "sunrise equation" (see e.g.
// https://en.wikipedia.org/wiki/Sunrise_equation): a low-precision (accurate
// to roughly a minute) but dependency-free way to get a day's sunrise/sunset
// for a given latitude/longitude. Pure arithmetic - no network call, ever.

var MS_PER_DAY = 86400000
var J1970 = 2440588      // Julian day number of the Unix epoch
var J2000 = 2451545      // Julian day number of 2000-01-01 12:00 UTC
var RAD = Math.PI / 180
var OBLIQUITY = RAD * 23.4397    // Earth's axial tilt
// Apparent altitude of the sun's centre at actual sunrise/sunset, once
// atmospheric refraction and the disk's own radius are accounted for.
var SOLAR_DISK_ALTITUDE = RAD * -0.833

function toJulian(date) { return date.getTime() / MS_PER_DAY - 0.5 + J1970 }
function fromJulian(j) { return new Date((j + 0.5 - J1970) * MS_PER_DAY) }
function daysSince2000(date) { return toJulian(date) - J2000 }

function solarMeanAnomaly(d) { return RAD * (357.5291 + 0.98560028 * d) }

function eclipticLongitude(meanAnomaly) {
  var center = RAD * (1.9148 * Math.sin(meanAnomaly) + 0.02 * Math.sin(2 * meanAnomaly) + 0.0003 * Math.sin(3 * meanAnomaly))
  var perihelion = RAD * 102.9372
  return meanAnomaly + center + perihelion + Math.PI
}

function declination(eclipticLon) { return Math.asin(Math.sin(eclipticLon) * Math.sin(OBLIQUITY)) }

function julianCycle(daysSinceEpoch, lonWestRad) {
  return Math.round(daysSinceEpoch - 0.0009 - lonWestRad / (2 * Math.PI))
}
function approxTransit(hourAngleRad, lonWestRad, cycle) {
  return 0.0009 + (hourAngleRad + lonWestRad) / (2 * Math.PI) + cycle
}
function solarTransitJulian(approxDays, meanAnomaly, eclipticLon) {
  return J2000 + approxDays + 0.0053 * Math.sin(meanAnomaly) - 0.0069 * Math.sin(2 * eclipticLon)
}

// Hour angle (radians) at which the sun reaches `altitude` for an observer
// at `latRad` when the sun's declination is `dec`. NaN (an out-of-range
// acos) means the sun never reaches that altitude that day - permanent day
// or night at that latitude/season (polar regions).
function hourAngle(altitude, latRad, dec) {
  return Math.acos((Math.sin(altitude) - Math.sin(latRad) * Math.sin(dec)) / (Math.cos(latRad) * Math.cos(dec)))
}

// A day's sunrise/sunset for a latitude/longitude, as ordinary local-time JS
// Dates. Either field is null when the sun doesn't cross the horizon that
// day (polar day/night, or no/invalid coordinates) - callers need a
// fallback for that case.
function sunTimesFor(date, lat, lon) {
  if (typeof lat !== "number" || typeof lon !== "number" || !isFinite(lat) || !isFinite(lon)) {
    return { sunrise: null, sunset: null }
  }
  var lonWest = RAD * -lon
  var latRad = RAD * lat
  var d = daysSince2000(date)
  var cycle = julianCycle(d, lonWest)
  var approxDays = approxTransit(0, lonWest, cycle)
  var meanAnomaly = solarMeanAnomaly(approxDays)
  var eclipticLon = eclipticLongitude(meanAnomaly)
  var dec = declination(eclipticLon)

  var w = hourAngle(SOLAR_DISK_ALTITUDE, latRad, dec)
  if (!isFinite(w)) return { sunrise: null, sunset: null }

  var setApproxDays = approxTransit(w, lonWest, cycle)
  var jSet = solarTransitJulian(setApproxDays, meanAnomaly, eclipticLon)
  var jNoon = solarTransitJulian(approxDays, meanAnomaly, eclipticLon)
  var jRise = jNoon - (jSet - jNoon)

  return { sunrise: fromJulian(jRise), sunset: fromJulian(jSet) }
}

// A slot's boundary time on one calendar day: its anchor event (sunrise or
// sunset) shifted by its offset in minutes. Null if that anchor didn't
// happen that day (polar edge case) - the caller tries adjacent days.
function boundaryTime(date, lat, lon, anchor, offsetMin) {
  var times = sunTimesFor(date, lat, lon)
  var base = anchor === "sunset" ? times.sunset : times.sunrise
  if (!base) return null
  return new Date(base.getTime() + (offsetMin || 0) * 60000)
}

var DAY_MS = 86400000

// Resolve which slot is active right now, and when the next one starts.
// Looks at yesterday/today/tomorrow's boundaries for every slot so midnight
// wraparound (e.g. a night slot whose boundary falls before midnight) works
// without special-casing. activeSlot is null when there is no schedule to
// run - no slots, no/invalid coordinates, or a polar edge case where none of
// the slot anchors happen. Callers treat null as "do nothing".
function computeSchedule(slots, lat, lon, now) {
  var list = Array.isArray(slots) ? slots : []
  if (list.length === 0) return { activeSlot: null, nextSlot: null, nextBoundaryTs: 0 }

  var boundaries = []
  for (var dayOffset = -1; dayOffset <= 1; dayOffset++) {
    var day = new Date(now.getTime() + dayOffset * DAY_MS)
    for (var i = 0; i < list.length; i++) {
      var t = boundaryTime(day, lat, lon, list[i].anchor, list[i].offsetMin)
      if (t) boundaries.push({ slot: list[i], ts: t.getTime() })
    }
  }

  if (boundaries.length === 0) {
    return { activeSlot: null, nextSlot: null, nextBoundaryTs: 0 }
  }

  boundaries.sort(function (a, b) { return a.ts - b.ts })

  var nowMs = now.getTime()
  var active = boundaries[boundaries.length - 1]
  var next = null
  for (var j = 0; j < boundaries.length; j++) {
    if (boundaries[j].ts <= nowMs) active = boundaries[j]
    else { next = boundaries[j]; break }
  }
  if (!next) next = boundaries[0]   // wrap to the earliest boundary computed (tomorrow's)

  return { activeSlot: active.slot, nextSlot: next.slot, nextBoundaryTs: next.ts }
}
