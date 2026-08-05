// =============================================================================
//  Nur Islam — main.dart
//  Kostenlos · werbefrei · offlinefähig · DE / TR / EN
//  Gebetszeiten nach Diyanet-Methode (Fecir 18°, Yatsı 17°),
//  optional Feinabgleich über eine Diyanet-Methoden-API (offline gecached).
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Globaler App-Zustand (bewusst ohne zusätzliche State-Management-Dependency).
final AppState appState = AppState();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appState.init();
  runApp(const NurIslamApp());
}

// =============================================================================
//  1. Lokalisierung (DE / TR / EN)
// =============================================================================

enum AppLang { de, tr, en }

const Map<String, List<String>> _strings = {
  // Reihenfolge: [de, tr, en]
  'app_name': ['Nur Islam', 'Nur Islam', 'Nur Islam'],
  'tab_times': ['Gebetszeiten', 'Namaz Vakitleri', 'Prayer Times'],
  'tab_qibla': ['Qibla', 'Kıble', 'Qibla'],
  'tab_tools': ['Tesbih', 'Tesbih', 'Tasbih'],
  'tab_qa': ['Frage & Antwort', 'Soru & Cevap', 'Q&A'],
  'tab_settings': ['Einstellungen', 'Ayarlar', 'Settings'],

  'p_fajr': ['Fadschr', 'İmsak', 'Fajr'],
  'p_sunrise': ['Sonnenaufgang', 'Güneş', 'Sunrise'],
  'p_dhuhr': ['Dhuhr', 'Öğle', 'Dhuhr'],
  'p_asr': ['Asr', 'İkindi', 'Asr'],
  'p_maghrib': ['Maghrib', 'Akşam', 'Maghrib'],
  'p_isha': ['Ischa', 'Yatsı', 'Isha'],

  'next_prayer': ['Nächstes Gebet', 'Sıradaki Vakit', 'Next Prayer'],
  'remaining': ['verbleibend', 'kaldı', 'remaining'],
  'now_running': ['Laufende Zeit', 'Şu anki vakit', 'Current period'],
  'today': ['Heute', 'Bugün', 'Today'],
  'motivation': ['Motivation des Tages', 'Günün Motivasyonu', 'Daily Motivation'],
  'source_local': [
    'Lokal berechnet · Diyanet-Methode (18° / 17°)',
    'Cihazda hesaplandı · Diyanet yöntemi (18° / 17°)',
    'Calculated on device · Diyanet method (18° / 17°)',
  ],
  'source_synced': [
    'Diyanet-Abgleich · offline gespeichert',
    'Diyanet eşitlemesi · çevrimdışı kayıtlı',
    'Diyanet sync · stored offline',
  ],

  // Standort
  'location': ['Standort', 'Konum', 'Location'],
  'location_loading': ['Standort wird ermittelt …', 'Konum alınıyor …', 'Getting location …'],
  'location_needed': [
    'Für Gebetszeiten und Qibla wird dein Standort benötigt.',
    'Namaz vakitleri ve kıble için konumun gerekli.',
    'Prayer times and qibla need your location.',
  ],
  'location_denied': [
    'Standortfreigabe abgelehnt. Erlaube den Zugriff, um fortzufahren.',
    'Konum izni reddedildi. Devam etmek için izin ver.',
    'Location permission denied. Allow access to continue.',
  ],
  'location_denied_forever': [
    'Standortzugriff dauerhaft blockiert. Aktiviere ihn in den Systemeinstellungen.',
    'Konum izni kalıcı olarak engellendi. Sistem ayarlarından aç.',
    'Location access is blocked. Enable it in your system settings.',
  ],
  'location_service_off': [
    'Ortungsdienste sind ausgeschaltet.',
    'Konum servisleri kapalı.',
    'Location services are turned off.',
  ],
  'allow_location': ['Standort freigeben', 'Konuma izin ver', 'Allow location'],
  'open_settings': ['Einstellungen öffnen', 'Ayarları aç', 'Open settings'],
  'refresh_location': ['Standort aktualisieren', 'Konumu güncelle', 'Refresh location'],
  'retry': ['Erneut versuchen', 'Tekrar dene', 'Try again'],

  // Qibla
  'qibla_title': ['Qibla-Richtung', 'Kıble Yönü', 'Qibla Direction'],
  'qibla_aligned': ['Ausgerichtet zur Kaaba', 'Kâbe\'ye yönelik', 'Aligned with the Kaaba'],
  'qibla_turn_left': ['Nach links drehen', 'Sola çevir', 'Turn left'],
  'qibla_turn_right': ['Nach rechts drehen', 'Sağa çevir', 'Turn right'],
  'qibla_distance': ['Entfernung zur Kaaba', 'Kâbe\'ye uzaklık', 'Distance to the Kaaba'],
  'qibla_hint': [
    'Halte das Gerät flach. Bewege es in einer Acht, falls die Nadel springt.',
    'Cihazı düz tut. İğne oynuyorsa cihazı sekiz çizerek hareket ettir.',
    'Hold the device flat. Move it in a figure eight if the needle jumps.',
  ],
  'no_compass': [
    'Dieses Gerät hat keinen Magnetsensor. Die Richtung wird als Gradzahl angezeigt.',
    'Bu cihazda manyetik sensör yok. Yön yalnızca derece olarak gösterilir.',
    'This device has no magnetometer. The direction is shown as degrees only.',
  ],
  'calibrate_needed': [
    'Kompass ungenau — bitte kalibrieren.',
    'Pusula hassas değil — lütfen kalibre et.',
    'Compass inaccurate — please calibrate.',
  ],

  // Q&A (gesperrt)
  'coming_soon': ['Kommt bald', 'Yakında', 'Coming soon'],
  'qa_locked_body': [
    'Frage & Antwort sowie Ayet- und Hadith-Inhalte werden vorbereitet und vor der '
        'Veröffentlichung auf ihre Quellen geprüft. Sie folgen in einem der nächsten '
        'Updates — kostenlos wie alles hier.',
    'Soru & Cevap ile ayet ve hadis içerikleri hazırlanıyor ve yayından önce '
        'kaynakları kontrol ediliyor. Yakın bir güncellemede eklenecek — her şey gibi ücretsiz.',
    'Q&A along with Qur\'an and hadith content is being prepared, with every source '
        'verified before release. It follows in one of the next updates — free, like everything here.',
  ],

  // Tesbih
  'tasbih_title': ['Tesbih', 'Tesbih', 'Tasbih'],
  'tasbih_target': ['Ziel', 'Hedef', 'Target'],
  'tasbih_reset': ['Zurücksetzen', 'Sıfırla', 'Reset'],
  'tasbih_round_done': ['Runde abgeschlossen', 'Tur tamamlandı', 'Round complete'],
  'tasbih_tap': ['Zum Zählen tippen', 'Saymak için dokun', 'Tap to count'],

  // Einstellungen
  'settings_language': ['Sprache', 'Dil', 'Language'],
  'settings_appearance': ['Darstellung', 'Görünüm', 'Appearance'],
  'theme_system': ['System', 'Sistem', 'System'],
  'theme_light': ['Hell', 'Açık', 'Light'],
  'theme_dark': ['Dunkel', 'Koyu', 'Dark'],
  'settings_calculation': ['Berechnung', 'Hesaplama', 'Calculation'],
  'settings_madhab': ['Asr-Berechnung', 'İkindi hesabı', 'Asr calculation'],
  'madhab_hanafi': ['Hanefi', 'Hanefi', 'Hanafi'],
  'madhab_shafii': ['Şafii / Maliki', 'Şafii / Maliki', 'Shafi\'i / Maliki'],
  'settings_offsets': ['Feinjustierung (± Minuten)', 'İnce ayar (± dakika)', 'Fine tuning (± minutes)'],
  'settings_offsets_hint': [
    'Nur nutzen, wenn deine Moschee bewusst abweichende Zeiten ansagt.',
    'Sadece camin farklı vakit okuyorsa kullan.',
    'Only use this if your mosque announces different times on purpose.',
  ],
  'settings_time_format': ['24-Stunden-Format', '24 saat biçimi', '24-hour format'],
  'settings_sync': ['Diyanet-Abgleich (online)', 'Diyanet eşitlemesi (çevrimiçi)', 'Diyanet sync (online)'],
  'settings_sync_hint': [
    'Lädt einmalig den Monatskalender nach Diyanet-Methode und speichert ihn offline.',
    'Diyanet yöntemine göre aylık takvimi bir kez indirir ve çevrimdışı saklar.',
    'Downloads the monthly calendar using the Diyanet method once and stores it offline.',
  ],
  'sync_now': ['Jetzt abgleichen', 'Şimdi eşitle', 'Sync now'],
  'syncing': ['Wird abgeglichen …', 'Eşitleniyor …', 'Syncing …'],
  'sync_ok': ['Abgleich abgeschlossen', 'Eşitleme tamamlandı', 'Sync complete'],
  'sync_failed': ['Abgleich fehlgeschlagen — offline berechnete Zeiten bleiben aktiv.',
    'Eşitleme başarısız — çevrimdışı hesaplanan vakitler geçerli.',
    'Sync failed — the offline calculation stays active.'],
  'last_sync': ['Letzter Abgleich', 'Son eşitleme', 'Last sync'],
  'never': ['Nie', 'Hiç', 'Never'],
  'settings_about': ['Über die App', 'Uygulama hakkında', 'About'],
  'about_body': [
    'Nur Islam ist dauerhaft kostenlos, ohne Werbung und ohne Tracking. '
        'Alle Zeiten werden auf dem Gerät berechnet und funktionieren offline.',
    'Nur Islam kalıcı olarak ücretsizdir, reklam ve takip içermez. '
        'Tüm vakitler cihazda hesaplanır ve çevrimdışı çalışır.',
    'Nur Islam is permanently free, with no ads and no tracking. '
        'All times are calculated on the device and work offline.',
  ],
  'km': ['km', 'km', 'km'],
};

String tr(String key) {
  final v = _strings[key];
  if (v == null) return key;
  return v[appState.lang.index];
}

const Map<AppLang, List<String>> _weekdays = {
  AppLang.de: ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'],
  AppLang.tr: ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'],
  AppLang.en: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'],
};

const Map<AppLang, List<String>> _months = {
  AppLang.de: ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August',
    'September', 'Oktober', 'November', 'Dezember'],
  AppLang.tr: ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos',
    'Eylül', 'Ekim', 'Kasım', 'Aralık'],
  AppLang.en: ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December'],
};

/// Himmelsrichtungs-Kürzel je Sprache (DE: N/NO/O/SO …, TR: K/KD/D/GD …).
const Map<AppLang, List<String>> _cardinals = {
  AppLang.de: ['N', 'NO', 'O', 'SO', 'S', 'SW', 'W', 'NW'],
  AppLang.tr: ['K', 'KD', 'D', 'GD', 'G', 'GB', 'B', 'KB'],
  AppLang.en: ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'],
};

String cardinalOf(double bearing) {
  final list = _cardinals[appState.lang]!;
  final idx = (((bearing % 360) + 22.5) ~/ 45) % 8;
  return list[idx];
}

String longDate(DateTime d) {
  final wd = _weekdays[appState.lang]![d.weekday - 1];
  final mo = _months[appState.lang]![d.month - 1];
  return appState.lang == AppLang.tr
      ? '${d.day} $mo $wd'
      : '$wd, ${d.day}. $mo ${d.year}';
}

/// Kurze, selbst formulierte Motivationstexte (keine Zitate, keine Übersetzungen).
const Map<AppLang, List<String>> _motivations = {
  AppLang.de: [
    'Ein kurzes Gebet zur rechten Zeit trägt weiter als ein langes zur falschen.',
    'Beginne klein und bleibe dabei — Beständigkeit schlägt Begeisterung.',
    'Dankbarkeit macht wenig zu viel.',
    'Wer seine Zeit nach dem Gebet ordnet, ordnet seinen ganzen Tag.',
    'Geduld ist keine Untätigkeit, sondern ruhiges Vertrauen.',
    'Ein freundliches Wort ist die kleinste Sadaqa und wirkt am längsten.',
    'Nimm dir heute einen Moment der Stille, bevor der Lärm beginnt.',
  ],
  AppLang.tr: [
    'Vaktinde kılınan kısa bir namaz, geç kalmış uzun bir namazdan hayırlıdır.',
    'Küçük başla ve devam et — süreklilik heyecandan güçlüdür.',
    'Şükür, azı çok yapar.',
    'Vaktini namaza göre düzenleyen, gününü de düzenler.',
    'Sabır tembellik değil, sakin bir güvendir.',
    'Güzel bir söz en küçük sadakadır ve en uzun kalır.',
    'Gürültü başlamadan önce bugün kendine bir sessizlik anı ayır.',
  ],
  AppLang.en: [
    'A short prayer on time carries further than a long one too late.',
    'Start small and keep going — consistency beats enthusiasm.',
    'Gratitude turns little into plenty.',
    'Order your time around prayer and the whole day falls into place.',
    'Patience is not idleness; it is calm trust.',
    'A kind word is the smallest charity and lasts the longest.',
    'Take a moment of quiet today, before the noise begins.',
  ],
};

String motivationOfTheDay(DateTime date) {
  final list = _motivations[appState.lang]!;
  final dayOfYear = date.difference(DateTime(date.year, 1, 1)).inDays;
  return list[dayOfYear % list.length];
}

// =============================================================================
//  2. Modelle
// =============================================================================

enum P { fajr, sunrise, dhuhr, asr, maghrib, isha }

extension PLabel on P {
  String get label => tr('p_$name');
  IconData get icon {
    switch (this) {
      case P.fajr:
        return Icons.nightlight_round;
      case P.sunrise:
        return Icons.wb_twilight;
      case P.dhuhr:
        return Icons.light_mode;
      case P.asr:
        return Icons.wb_sunny_outlined;
      case P.maghrib:
        return Icons.wb_twilight_outlined;
      case P.isha:
        return Icons.dark_mode_outlined;
    }
  }
}

class DayTimes {
  final DateTime date;
  final Map<P, DateTime> times;
  final bool synced;

  const DayTimes({required this.date, required this.times, required this.synced});

  DateTime? operator [](P p) => times[p];

  /// Gebetszeiten ohne Sonnenaufgang (dieser ist kein Gebet, sondern Endmarke).
  List<P> get prayersOnly => const [P.fajr, P.dhuhr, P.asr, P.maghrib, P.isha];
}

enum LocState { unknown, loading, ready, serviceOff, denied, deniedForever, error }

// =============================================================================
//  3. Gebetszeiten-Berechnung (offline, Diyanet-Winkel 18° / 17°)
// =============================================================================
//  Klassisches Winkelverfahren: Sonnendeklination + Zeitgleichung, daraus
//  Stundenwinkel für den jeweiligen Sonnenstand. Diyanet verwendet
//  Fecir 18°, Yatsı 17°; İkindi standardmäßig nach hanefitischem Schattenmaß.
// =============================================================================

double _dsin(double d) => math.sin(d * math.pi / 180);
double _dcos(double d) => math.cos(d * math.pi / 180);
double _dtan(double d) => math.tan(d * math.pi / 180);
double _dasin(double x) => math.asin(x) * 180 / math.pi;
double _dacos(double x) => math.acos(x) * 180 / math.pi;
double _datan2(double y, double x) => math.atan2(y, x) * 180 / math.pi;
double _dacot(double x) => math.atan2(1, x) * 180 / math.pi;

double _fixAngle(double a) {
  a = a - 360 * (a / 360).floor();
  return a < 0 ? a + 360 : a;
}

double _fixHour(double h) {
  h = h - 24 * (h / 24).floor();
  return h < 0 ? h + 24 : h;
}

class _SunPos {
  final double declination;
  final double equationOfTime;
  const _SunPos(this.declination, this.equationOfTime);
}

class PrayerCalculator {
  static const double fajrAngle = 18.0; // Diyanet
  static const double ishaAngle = 17.0; // Diyanet
  static const double sunriseAngle = 0.833; // Refraktion + Sonnenradius

  static double _julianDay(int year, int month, int day) {
    if (month <= 2) {
      year -= 1;
      month += 12;
    }
    final a = (year / 100).floor();
    final b = 2 - a + (a / 4).floor();
    return (365.25 * (year + 4716)).floor().toDouble() +
        (30.6001 * (month + 1)).floor().toDouble() +
        day +
        b -
        1524.5;
  }

  static _SunPos _sunPosition(double jd) {
    final d = jd - 2451545.0;
    final g = _fixAngle(357.529 + 0.98560028 * d);
    final q = _fixAngle(280.459 + 0.98564736 * d);
    final l = _fixAngle(q + 1.915 * _dsin(g) + 0.020 * _dsin(2 * g));
    final e = 23.439 - 0.00000036 * d;
    final ra = _fixHour(_datan2(_dcos(e) * _dsin(l), _dcos(l)) / 15);
    final decl = _dasin(_dsin(e) * _dsin(l));
    final eqt = q / 15 - ra;
    return _SunPos(decl, eqt);
  }

  static double _midDay(double jd, double t) {
    final eqt = _sunPosition(jd + t).equationOfTime;
    return _fixHour(12 - eqt);
  }

  /// Zeitpunkt (in Stunden), an dem die Sonne den gegebenen Höhenwinkel erreicht.
  static double _sunAngleTime(double jd, double t, double angle, double lat,
      {bool beforeNoon = false}) {
    final decl = _sunPosition(jd + t).declination;
    final numerator = -_dsin(angle) - _dsin(decl) * _dsin(lat);
    final denominator = _dcos(decl) * _dcos(lat);
    final v = numerator / denominator;
    if (v.isNaN || v.abs() > 1) return double.nan; // Polarregionen
    final ha = _dacos(v) / 15;
    final noon = _midDay(jd, t);
    return beforeNoon ? noon - ha : noon + ha;
  }

  static double _asrTime(double jd, double t, int shadowFactor, double lat) {
    final decl = _sunPosition(jd + t).declination;
    final angle = -_dacot(shadowFactor + _dtan((lat - decl).abs()));
    return _sunAngleTime(jd, t, angle, lat);
  }

  /// Liefert die Zeiten des Tages. [shadowFactor] 2 = hanefitisch, 1 = şafii.
  static DayTimes compute({
    required DateTime date,
    required double lat,
    required double lng,
    required int shadowFactor,
    Map<P, int> offsets = const {},
  }) {
    final day = DateTime(date.year, date.month, date.day);
    final tzHours = day.timeZoneOffset.inMinutes / 60.0;
    final jd = _julianDay(day.year, day.month, day.day) - lng / (15 * 24);

    // Startschätzungen in Tagesbruchteilen, danach zwei Iterationen.
    var tFajr = 5 / 24, tSunrise = 6 / 24, tDhuhr = 12 / 24;
    var tAsr = 13 / 24, tMaghrib = 18 / 24, tIsha = 18 / 24;

    for (var i = 0; i < 2; i++) {
      tFajr = _sunAngleTime(jd, tFajr, fajrAngle, lat, beforeNoon: true) / 24;
      tSunrise = _sunAngleTime(jd, tSunrise, sunriseAngle, lat, beforeNoon: true) / 24;
      tDhuhr = _midDay(jd, tDhuhr) / 24;
      tAsr = _asrTime(jd, tAsr, shadowFactor, lat) / 24;
      tMaghrib = _sunAngleTime(jd, tMaghrib, sunriseAngle, lat) / 24;
      tIsha = _sunAngleTime(jd, tIsha, ishaAngle, lat) / 24;
    }

    DateTime? toLocal(double tDays, P key) {
      final hours = tDays * 24;
      if (hours.isNaN) return null;
      final local = hours + tzHours - lng / 15;
      final minutes = (local * 60).round() + (offsets[key] ?? 0);
      return day.add(Duration(minutes: minutes));
    }

    // Dhuhr erhält eine Minute Sicherheitsaufschlag (Diyanet-Praxis "temkin").
    final map = <P, DateTime>{};
    void put(P k, DateTime? v) {
      if (v != null) map[k] = v;
    }

    put(P.fajr, toLocal(tFajr, P.fajr));
    put(P.sunrise, toLocal(tSunrise, P.sunrise));
    put(P.dhuhr, toLocal(tDhuhr + 1 / (24 * 60), P.dhuhr));
    put(P.asr, toLocal(tAsr, P.asr));
    put(P.maghrib, toLocal(tMaghrib, P.maghrib));
    put(P.isha, toLocal(tIsha, P.isha));

    return DayTimes(date: day, times: map, synced: false);
  }
}

// =============================================================================
//  4. Qibla-Berechnung
// =============================================================================

class Qibla {
  /// Kaaba, Mekka.
  static const double kaabaLat = 21.4224779;
  static const double kaabaLng = 39.8251832;

  /// Anfangspeilung (Großkreis) vom Standort zur Kaaba, 0–360° ab Nord.
  static double bearing(double lat, double lng) {
    final phi1 = lat * math.pi / 180;
    final phi2 = kaabaLat * math.pi / 180;
    final dLng = (kaabaLng - lng) * math.pi / 180;
    final y = math.sin(dLng);
    final x = math.cos(phi1) * math.tan(phi2) - math.sin(phi1) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  /// Entfernung zur Kaaba in Kilometern (Haversine).
  static double distanceKm(double lat, double lng) {
    const r = 6371.0;
    final dLat = (kaabaLat - lat) * math.pi / 180;
    final dLng = (kaabaLng - lng) * math.pi / 180;
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat * math.pi / 180) *
            math.cos(kaabaLat * math.pi / 180) *
            math.pow(math.sin(dLng / 2), 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Kürzeste vorzeichenbehaftete Differenz zweier Winkel (-180 … +180).
  static double delta(double from, double to) {
    return ((to - from + 540) % 360) - 180;
  }
}

// =============================================================================
//  5. App-Zustand & Persistenz
// =============================================================================

class AppState extends ChangeNotifier {
  AppLang lang = AppLang.de;
  ThemeMode themeMode = ThemeMode.dark;
  bool use24h = true;
  bool hanafiAsr = true;
  bool useDiyanetSync = false;

  double? lat;
  double? lng;
  LocState locState = LocState.unknown;

  Map<P, int> offsets = {for (final p in P.values) p: 0};

  /// "yyyy-MM-dd" -> ["04:23","05:57","13:31","17:22","21:02","22:48"]
  Map<String, List<String>> syncedTimes = {};
  DateTime? lastSync;
  bool syncing = false;

  // Tesbih
  int tasbihCount = 0;
  int tasbihTarget = 33;
  int dhikrIndex = 0;

  late SharedPreferences _prefs;

  static const _dhikr = [
    'Subhânallâh',
    'Elhamdülillâh',
    'Allâhu ekber',
    'Lâ ilâhe illallâh',
    'Estağfirullâh',
  ];
  String get currentDhikr => _dhikr[dhikrIndex % _dhikr.length];
  List<String> get dhikrList => _dhikr;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    lang = AppLang.values[_prefs.getInt('lang') ?? 0];
    themeMode = ThemeMode.values[_prefs.getInt('theme') ?? ThemeMode.dark.index];
    use24h = _prefs.getBool('use24h') ?? true;
    hanafiAsr = _prefs.getBool('hanafiAsr') ?? true;
    useDiyanetSync = _prefs.getBool('useSync') ?? false;
    lat = _prefs.getDouble('lat');
    lng = _prefs.getDouble('lng');
    if (lat != null && lng != null) locState = LocState.ready;
    tasbihCount = _prefs.getInt('tasbihCount') ?? 0;
    tasbihTarget = _prefs.getInt('tasbihTarget') ?? 33;
    dhikrIndex = _prefs.getInt('dhikrIndex') ?? 0;

    final rawOffsets = _prefs.getString('offsets');
    if (rawOffsets != null) {
      final decoded = jsonDecode(rawOffsets) as Map<String, dynamic>;
      for (final p in P.values) {
        offsets[p] = (decoded[p.name] as num?)?.toInt() ?? 0;
      }
    }
    final rawSync = _prefs.getString('syncedTimes');
    if (rawSync != null) {
      final decoded = jsonDecode(rawSync) as Map<String, dynamic>;
      syncedTimes = decoded.map((k, v) => MapEntry(k, List<String>.from(v as List)));
    }
    final ls = _prefs.getInt('lastSync');
    if (ls != null) lastSync = DateTime.fromMillisecondsSinceEpoch(ls);
  }

  void setLang(AppLang v) {
    lang = v;
    _prefs.setInt('lang', v.index);
    notifyListeners();
  }

  void setTheme(ThemeMode v) {
    themeMode = v;
    _prefs.setInt('theme', v.index);
    notifyListeners();
  }

  void setUse24h(bool v) {
    use24h = v;
    _prefs.setBool('use24h', v);
    notifyListeners();
  }

  void setHanafiAsr(bool v) {
    hanafiAsr = v;
    _prefs.setBool('hanafiAsr', v);
    notifyListeners();
  }

  void setOffset(P p, int minutes) {
    offsets[p] = minutes.clamp(-30, 30);
    _prefs.setString('offsets',
        jsonEncode({for (final e in offsets.entries) e.key.name: e.value}));
    notifyListeners();
  }

  void setUseSync(bool v) {
    useDiyanetSync = v;
    _prefs.setBool('useSync', v);
    notifyListeners();
  }

  // --- Tesbih ---------------------------------------------------------------
  void tasbihIncrement() {
    tasbihCount++;
    _prefs.setInt('tasbihCount', tasbihCount);
    if (tasbihTarget > 0 && tasbihCount % tasbihTarget == 0) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.selectionClick();
    }
    notifyListeners();
  }

  void tasbihReset() {
    tasbihCount = 0;
    _prefs.setInt('tasbihCount', 0);
    notifyListeners();
  }

  void setTasbihTarget(int v) {
    tasbihTarget = v;
    _prefs.setInt('tasbihTarget', v);
    notifyListeners();
  }

  void setDhikrIndex(int v) {
    dhikrIndex = v;
    _prefs.setInt('dhikrIndex', v);
    notifyListeners();
  }

  // --- Standort -------------------------------------------------------------
  Future<void> refreshLocation() async {
    locState = LocState.loading;
    notifyListeners();
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        locState = LocState.serviceOff;
        notifyListeners();
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        locState = LocState.deniedForever;
        notifyListeners();
        return;
      }
      if (permission == LocationPermission.denied) {
        locState = LocState.denied;
        notifyListeners();
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 25),
        ),
      );
      lat = pos.latitude;
      lng = pos.longitude;
      await _prefs.setDouble('lat', lat!);
      await _prefs.setDouble('lng', lng!);
      locState = LocState.ready;
      notifyListeners();
      if (useDiyanetSync) unawaited(syncDiyanet());
    } catch (_) {
      // Fällt auf den gecachten Standort zurück, falls vorhanden.
      locState = (lat != null && lng != null) ? LocState.ready : LocState.error;
      notifyListeners();
    }
  }

  // --- Diyanet-Abgleich -----------------------------------------------------
  /// Lädt den Monatskalender nach Diyanet-Methode (method=13) und legt ihn
  /// offline ab. Schlägt der Aufruf fehl, bleibt die lokale Berechnung aktiv.
  Future<bool> syncDiyanet() async {
    if (lat == null || lng == null || syncing) return false;
    syncing = true;
    notifyListeners();
    var ok = false;
    try {
      final now = DateTime.now();
      for (var i = 0; i < 2; i++) {
        final d = DateTime(now.year, now.month + i, 1);
        final uri = Uri.https('api.aladhan.com', '/v1/calendar', {
          'latitude': '$lat',
          'longitude': '$lng',
          'method': '13', // Diyanet İşleri Başkanlığı
          'school': hanafiAsr ? '1' : '0',
          'month': '${d.month}',
          'year': '${d.year}',
        });
        final res = await http.get(uri).timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) continue;
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final data = body['data'] as List<dynamic>;
        for (final entry in data) {
          final e = entry as Map<String, dynamic>;
          final greg = e['date']['gregorian']['date'] as String; // dd-MM-yyyy
          final parts = greg.split('-');
          final key = '${parts[2]}-${parts[1]}-${parts[0]}';
          final t = e['timings'] as Map<String, dynamic>;
          String clean(String s) => s.split(' ').first.trim();
          syncedTimes[key] = [
            clean(t['Fajr'] as String),
            clean(t['Sunrise'] as String),
            clean(t['Dhuhr'] as String),
            clean(t['Asr'] as String),
            clean(t['Maghrib'] as String),
            clean(t['Isha'] as String),
          ];
        }
        ok = true;
      }
      if (ok) {
        // Alte Einträge aufräumen (nur letzte 70 Tage behalten).
        final cutoff = DateTime.now().subtract(const Duration(days: 70));
        syncedTimes.removeWhere((k, _) {
          final d = DateTime.tryParse(k);
          return d != null && d.isBefore(cutoff);
        });
        lastSync = DateTime.now();
        await _prefs.setString('syncedTimes', jsonEncode(syncedTimes));
        await _prefs.setInt('lastSync', lastSync!.millisecondsSinceEpoch);
      }
    } catch (_) {
      ok = false;
    }
    syncing = false;
    notifyListeners();
    return ok;
  }

  // --- Zeiten abrufen -------------------------------------------------------
  String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DayTimes? timesFor(DateTime date) {
    if (lat == null || lng == null) return null;
    final day = DateTime(date.year, date.month, date.day);

    if (useDiyanetSync) {
      final cached = syncedTimes[_dayKey(day)];
      if (cached != null && cached.length == 6) {
        final map = <P, DateTime>{};
        for (var i = 0; i < 6; i++) {
          final hm = cached[i].split(':');
          final h = int.tryParse(hm[0]);
          final m = int.tryParse(hm.length > 1 ? hm[1] : '');
          if (h == null || m == null) continue;
          final key = P.values[i];
          map[key] = day.add(Duration(hours: h, minutes: m + (offsets[key] ?? 0)));
        }
        if (map.length == 6) {
          return DayTimes(date: day, times: map, synced: true);
        }
      }
    }

    return PrayerCalculator.compute(
      date: day,
      lat: lat!,
      lng: lng!,
      shadowFactor: hanafiAsr ? 2 : 1,
      offsets: offsets,
    );
  }

  /// Nächstes Gebet (Sonnenaufgang ausgenommen) inkl. Datum über Mitternacht.
  MapEntry<P, DateTime>? nextPrayer(DateTime now) {
    final today = timesFor(now);
    if (today == null) return null;
    for (final p in today.prayersOnly) {
      final t = today[p];
      if (t != null && t.isAfter(now)) return MapEntry(p, t);
    }
    final tomorrow = timesFor(now.add(const Duration(days: 1)));
    final f = tomorrow?[P.fajr];
    return f == null ? null : MapEntry(P.fajr, f);
  }

  /// Zuletzt begonnene Zeit — für die Fortschrittsanzeige.
  MapEntry<P, DateTime>? currentPeriod(DateTime now) {
    final today = timesFor(now);
    if (today == null) return null;
    MapEntry<P, DateTime>? last;
    for (final p in P.values) {
      final t = today[p];
      if (t != null && !t.isAfter(now)) last = MapEntry(p, t);
    }
    if (last != null) return last;
    final yesterday = timesFor(now.subtract(const Duration(days: 1)));
    final i = yesterday?[P.isha];
    return i == null ? null : MapEntry(P.isha, i);
  }
}

String fmtTime(DateTime? t) {
  if (t == null) return '—';
  if (appState.use24h) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
  final h24 = t.hour;
  final h = h24 % 12 == 0 ? 12 : h24 % 12;
  final suffix = h24 < 12 ? 'AM' : 'PM';
  return '$h:${t.minute.toString().padLeft(2, '0')} $suffix';
}

String fmtDuration(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

// =============================================================================
//  6. Theme
// =============================================================================

const Color kGreen = Color(0xFF0F382C); // Islamisches Grün
const Color kGold = Color(0xFFD4AF37); // Gold
const Color kDeep = Color(0xFF0A1C16); // Dunkler Hintergrund
const Color kSurface = Color(0xFF132A22); // Kartenfläche (dunkel)
const Color kMid = Color(0xFF1B4D3E); // Sekundär

ThemeData _theme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: kGreen,
    brightness: b,
    primary: dark ? kGold : kGreen,
    secondary: dark ? kMid : kGold,
    surface: dark ? kSurface : Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? kDeep : const Color(0xFFF7F6F1),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: kGold.withValues(alpha: dark ? 0.20 : 0.0)),
      ),
      color: dark ? kSurface : Colors.white,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? kDeep : Colors.white,
      indicatorColor: kGold.withValues(alpha: 0.18),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 11, color: dark ? Colors.white70 : null),
      ),
    ),
    listTileTheme: const ListTileThemeData(dense: false),
  );
}

// =============================================================================
//  7. App-Gerüst
// =============================================================================

class NurIslamApp extends StatelessWidget {
  const NurIslamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        return MaterialApp(
          title: 'Nur Islam',
          debugShowCheckedModeBanner: false,
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          themeMode: appState.themeMode,
          home: const RootShell(),
        );
      },
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (appState.locState != LocState.ready) {
        appState.refreshLocation();
      } else if (appState.useDiyanetSync &&
          (appState.lastSync == null ||
              DateTime.now().difference(appState.lastSync!).inDays >= 7)) {
        appState.syncDiyanet();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = const [
      TimesTab(),
      QiblaTab(),
      TasbihTab(),
      QaLockedTab(),
      SettingsTab(),
    ];

    return Scaffold(
      body: SafeArea(bottom: false, child: pages[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.schedule_outlined),
            selectedIcon: const Icon(Icons.schedule),
            label: tr('tab_times'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.explore_outlined),
            selectedIcon: const Icon(Icons.explore),
            label: tr('tab_qibla'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.radio_button_unchecked),
            selectedIcon: const Icon(Icons.circle_outlined),
            label: tr('tab_tools'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.lock_outline),
            selectedIcon: const Icon(Icons.lock),
            label: tr('tab_qa'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: tr('tab_settings'),
          ),
        ],
      ),
    );
  }
}

/// Einheitlicher Seitenkopf.
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const PageHeader({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

/// Wiederverwendbarer Hinweis, wenn kein Standort vorliegt.
class LocationNotice extends StatelessWidget {
  const LocationNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final s = appState.locState;
    String message;
    String action = tr('allow_location');

    switch (s) {
      case LocState.loading:
        return Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(tr('location_loading')),
            ],
          ),
        );
      case LocState.serviceOff:
        message = tr('location_service_off');
        action = tr('open_settings');
        break;
      case LocState.denied:
        message = tr('location_denied');
        break;
      case LocState.deniedForever:
        message = tr('location_denied_forever');
        action = tr('open_settings');
        break;
      case LocState.error:
        message = tr('location_needed');
        action = tr('retry');
        break;
      default:
        message = tr('location_needed');
    }

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_off_outlined,
              size: 44, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 14),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () {
              if (s == LocState.serviceOff) {
                Geolocator.openLocationSettings();
              } else if (s == LocState.deniedForever) {
                Geolocator.openAppSettings();
              } else {
                appState.refreshLocation();
              }
            },
            icon: const Icon(Icons.my_location),
            label: Text(action),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
//  8. Tab 1 — Gebetszeiten, nächstes Gebet, Countdown, Motivation
// =============================================================================

class TimesTab extends StatefulWidget {
  const TimesTab({super.key});

  @override
  State<TimesTab> createState() => _TimesTabState();
}

class _TimesTabState extends State<TimesTab> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final day = appState.timesFor(_now);

    return RefreshIndicator(
      onRefresh: () async {
        await appState.refreshLocation();
        if (appState.useDiyanetSync) await appState.syncDiyanet();
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          PageHeader(title: tr('tab_times'), subtitle: longDate(_now)),
          if (day == null)
            const LocationNotice()
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _NextPrayerCard(now: _now, day: day),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Card(
                child: Column(
                  children: [
                    for (final p in P.values) _PrayerRow(p: p, day: day, now: _now),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.auto_awesome_outlined, size: 18, color: kGold),
                          const SizedBox(width: 8),
                          Text(tr('motivation'),
                              style: theme.textTheme.labelLarge
                                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(motivationOfTheDay(_now),
                          style: theme.textTheme.titleMedium?.copyWith(height: 1.4)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Icon(day.synced ? Icons.cloud_done_outlined : Icons.offline_bolt_outlined,
                      size: 15, color: theme.colorScheme.outline),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      day.synced ? tr('source_synced') : tr('source_local'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Icon(Icons.place_outlined, size: 15, color: theme.colorScheme.outline),
                  const SizedBox(width: 6),
                  Text(
                    '${appState.lat!.toStringAsFixed(3)}°, ${appState.lng!.toStringAsFixed(3)}°',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NextPrayerCard extends StatelessWidget {
  final DateTime now;
  final DayTimes day;
  const _NextPrayerCard({required this.now, required this.day});

  @override
  Widget build(BuildContext context) {
    final next = appState.nextPrayer(now);
    final current = appState.currentPeriod(now);
    if (next == null) return const SizedBox.shrink();

    final remaining = next.value.difference(now);
    double progress = 0;
    if (current != null) {
      final total = next.value.difference(current.value).inSeconds;
      final done = now.difference(current.value).inSeconds;
      if (total > 0) progress = (done / total).clamp(0.0, 1.0);
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kGreen, kDeep],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('next_prayer'),
              style: const TextStyle(
                  color: Colors.white70, fontSize: 12, letterSpacing: 1.2)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(next.key.icon, color: kGold, size: 26),
              const SizedBox(width: 10),
              Text(next.key.label,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(fmtTime(next.value),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 26, fontWeight: FontWeight.w300)),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(kGold),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.hourglass_bottom, color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              Text(fmtDuration(remaining),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()])),
              const SizedBox(width: 8),
              Text(tr('remaining'),
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrayerRow extends StatelessWidget {
  final P p;
  final DayTimes day;
  final DateTime now;
  const _PrayerRow({required this.p, required this.day, required this.now});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = appState.currentPeriod(now);
    final isCurrent = current?.key == p;
    final time = day[p];

    return Container(
      decoration: BoxDecoration(
        color: isCurrent ? theme.colorScheme.primary.withValues(alpha: 0.09) : null,
        borderRadius: BorderRadius.circular(14),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Row(
        children: [
          Icon(p.icon,
              size: 20,
              color: isCurrent ? theme.colorScheme.primary : theme.colorScheme.outline),
          const SizedBox(width: 14),
          Expanded(
            child: Text(p.label,
                style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500)),
          ),
          Text(fmtTime(time),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ],
      ),
    );
  }
}

// =============================================================================
//  9. Tab 2 — Qibla-Finder (voll funktionsfähig)
// =============================================================================

class QiblaTab extends StatefulWidget {
  const QiblaTab({super.key});

  @override
  State<QiblaTab> createState() => _QiblaTabState();
}

class _QiblaTabState extends State<QiblaTab> {
  double? _heading; // geglättete Geräteausrichtung in Grad ab Nord
  double? _accuracy;
  bool _wasAligned = false;
  StreamSubscription<CompassEvent>? _sub;
  bool _sensorMissing = false;

  static const double _alignTolerance = 3.0; // Grad

  @override
  void initState() {
    super.initState();
    final stream = FlutterCompass.events;
    if (stream == null) {
      _sensorMissing = true;
    } else {
      _sub = stream.listen((event) {
        final h = event.heading;
        if (h == null) {
          if (mounted && !_sensorMissing) setState(() => _sensorMissing = true);
          return;
        }
        final smoothed = _heading == null ? h : _smooth(_heading!, h, 0.25);
        if (mounted) {
          setState(() {
            _heading = smoothed;
            _accuracy = event.accuracy;
            _sensorMissing = false;
          });
        }
      });
    }
  }

  /// Exponentielle Glättung mit korrektem Überlauf bei 0°/360°.
  double _smooth(double prev, double next, double factor) {
    final diff = Qibla.delta(prev, next);
    return (prev + diff * factor + 360) % 360;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (appState.lat == null || appState.lng == null) {
      return ListView(children: [
        PageHeader(title: tr('qibla_title')),
        const LocationNotice(),
      ]);
    }

    final bearing = Qibla.bearing(appState.lat!, appState.lng!);
    final distance = Qibla.distanceKm(appState.lat!, appState.lng!);
    final heading = _heading;
    final delta = heading == null ? null : Qibla.delta(heading, bearing);
    final aligned = delta != null && delta.abs() <= _alignTolerance;

    // Haptisches Signal genau beim Einrasten.
    if (aligned && !_wasAligned) {
      HapticFeedback.mediumImpact();
      _wasAligned = true;
    } else if (!aligned && _wasAligned) {
      _wasAligned = false;
    }

    String status;
    Color statusColor;
    if (heading == null) {
      status = tr('no_compass');
      statusColor = theme.colorScheme.outline;
    } else if (aligned) {
      status = tr('qibla_aligned');
      statusColor = const Color(0xFF1E9E6A);
    } else if (delta! > 0) {
      status = '${tr('qibla_turn_right')}  ${delta.abs().toStringAsFixed(0)}°';
      statusColor = theme.colorScheme.onSurfaceVariant;
    } else {
      status = '${tr('qibla_turn_left')}  ${delta.abs().toStringAsFixed(0)}°';
      statusColor = theme.colorScheme.onSurfaceVariant;
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        PageHeader(title: tr('qibla_title'), subtitle: tr('qibla_hint')),
        const SizedBox(height: 8),

        // --- Kompass mit Gebetsteppich-Nadel ---------------------------------
        Center(
          child: SizedBox(
            width: 320,
            height: 320,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Drehende Skala: Norden wandert entgegen der Geräteausrichtung.
                Transform.rotate(
                  angle: -((heading ?? 0) * math.pi / 180),
                  child: CustomPaint(
                    size: const Size(320, 320),
                    painter: CompassDialPainter(
                      qiblaBearing: bearing,
                      isDark: theme.brightness == Brightness.dark,
                      onSurface: theme.colorScheme.onSurface,
                      outline: theme.colorScheme.outlineVariant,
                    ),
                  ),
                ),
                // Gebetsteppich: Oberseite (Mihrab) zeigt zur Kaaba.
                Transform.rotate(
                  angle: ((bearing - (heading ?? 0)) * math.pi / 180),
                  child: SizedBox(
                    width: 132,
                    height: 208,
                    child: CustomPaint(
                      painter: PrayerRugNeedlePainter(aligned: aligned),
                    ),
                  ),
                ),
                // Feststehende Indexmarke oben (Blickrichtung des Geräts).
                Positioned(
                  top: 0,
                  child: Icon(Icons.arrow_drop_down,
                      size: 34, color: aligned ? const Color(0xFF1E9E6A) : kGold),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // --- Gradzahl --------------------------------------------------------
        Center(
          child: Text(
            '${bearing.toStringAsFixed(0)}° ${cardinalOf(bearing)}',
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // --- Status ----------------------------------------------------------
        Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              color: aligned
                  ? const Color(0xFF1E9E6A).withValues(alpha: 0.14)
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(aligned ? Icons.check_circle : Icons.rotate_right,
                    size: 18, color: statusColor),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(status,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall?.copyWith(
                          color: statusColor, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),

        if (_accuracy != null && _accuracy! > 20) ...[
          const SizedBox(height: 10),
          Center(
            child: Text(tr('calibrate_needed'),
                style: theme.textTheme.bodySmall?.copyWith(color: kGold)),
          ),
        ],

        const SizedBox(height: 22),

        // --- Detailkarte -----------------------------------------------------
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.explore_outlined),
                  title: Text(tr('qibla_title')),
                  trailing: Text('${bearing.toStringAsFixed(1)}°',
                      style: theme.textTheme.titleMedium),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.straighten),
                  title: Text(tr('qibla_distance')),
                  trailing: Text('${distance.toStringAsFixed(0)} ${tr('km')}',
                      style: theme.textTheme.titleMedium),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: Text(tr('location')),
                  subtitle: Text(
                      '${appState.lat!.toStringAsFixed(4)}°, ${appState.lng!.toStringAsFixed(4)}°'),
                  trailing: IconButton(
                    icon: const Icon(Icons.my_location),
                    tooltip: tr('refresh_location'),
                    onPressed: () => appState.refreshLocation(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Kompassskala mit Gradstrichen, Himmelsrichtungen und Kaaba-Marke.
class CompassDialPainter extends CustomPainter {
  final double qiblaBearing;
  final bool isDark;
  final Color onSurface;
  final Color outline;

  CompassDialPainter({
    required this.qiblaBearing,
    required this.isDark,
    required this.onSurface,
    required this.outline,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;

    // Hintergrundscheibe
    final disc = Paint()
      ..shader = RadialGradient(
        colors: isDark
            ? [const Color(0xFF16261F), const Color(0xFF0C1815)]
            : [Colors.white, const Color(0xFFEFEDE6)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, disc);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = outline,
    );
    canvas.drawCircle(
      center,
      radius - 26,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = outline.withValues(alpha: 0.6),
    );

    // Gradstriche alle 5°, betont alle 45°
    for (var deg = 0; deg < 360; deg += 5) {
      final major = deg % 45 == 0;
      final len = major ? 14.0 : 6.0;
      final rad = (deg - 90) * math.pi / 180;
      final p1 = center + Offset(math.cos(rad), math.sin(rad)) * (radius - 2);
      final p2 = center + Offset(math.cos(rad), math.sin(rad)) * (radius - 2 - len);
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..strokeWidth = major ? 2.0 : 1.0
          ..color = major ? onSurface.withValues(alpha: 0.7) : outline,
      );
    }

    // Himmelsrichtungen
    final labels = _cardinals[appState.lang]!;
    for (var i = 0; i < 8; i++) {
      final deg = i * 45.0;
      final rad = (deg - 90) * math.pi / 180;
      final pos = center + Offset(math.cos(rad), math.sin(rad)) * (radius - 34);
      final isNorth = i == 0;
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            fontSize: isNorth ? 17 : 13,
            fontWeight: isNorth ? FontWeight.w800 : FontWeight.w500,
            color: isNorth ? const Color(0xFFC0392B) : onSurface.withValues(alpha: 0.75),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(deg * math.pi / 180);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    // Kaaba-Marke exakt auf der Qibla-Peilung
    final qRad = (qiblaBearing - 90) * math.pi / 180;
    final qPos = center + Offset(math.cos(qRad), math.sin(qRad)) * (radius - 15);
    canvas.save();
    canvas.translate(qPos.dx, qPos.dy);
    canvas.rotate(qiblaBearing * math.pi / 180);
    final cube = Rect.fromCenter(center: Offset.zero, width: 15, height: 15);
    canvas.drawRRect(
      RRect.fromRectAndRadius(cube, const Radius.circular(2)),
      Paint()..color = isDark ? const Color(0xFF1B1B1B) : const Color(0xFF141414),
    );
    canvas.drawLine(
      Offset(-7.5, -2.5),
      Offset(7.5, -2.5),
      Paint()
        ..color = kGold
        ..strokeWidth = 2.2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CompassDialPainter old) =>
      old.qiblaBearing != qiblaBearing ||
      old.isDark != isDark ||
      old.onSurface != onSurface;
}

/// Stilisierter Gebetsteppich als Kompassnadel.
/// Die Kopfseite (Mihrab-Bogen, oben im Canvas) zeigt zur Kaaba.
class PrayerRugNeedlePainter extends CustomPainter {
  final bool aligned;
  PrayerRugNeedlePainter({required this.aligned});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Teppichumriss: Rechteck mit Mihrab-Bogen an der Kopfseite.
    final rug = Path()
      ..moveTo(w * 0.08, h * 0.94)
      ..lineTo(w * 0.08, h * 0.36)
      ..cubicTo(w * 0.08, h * 0.10, w * 0.30, h * 0.03, w * 0.5, h * 0.03)
      ..cubicTo(w * 0.70, h * 0.03, w * 0.92, h * 0.10, w * 0.92, h * 0.36)
      ..lineTo(w * 0.92, h * 0.94)
      ..close();

    // Schatten
    canvas.drawPath(
      rug.shift(const Offset(0, 4)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Grundfläche
    final base = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: aligned
            ? const [Color(0xFF19A06B), Color(0xFF0B5D3D)]
            : const [Color(0xFF13805E), Color(0xFF073B29)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(rug, base);

    // Äußere Goldkante
    canvas.drawPath(
      rug,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = kGold,
    );

    // Innere Bordüre
    final inner = Path()
      ..moveTo(w * 0.17, h * 0.88)
      ..lineTo(w * 0.17, h * 0.38)
      ..cubicTo(w * 0.17, h * 0.17, w * 0.33, h * 0.12, w * 0.5, h * 0.12)
      ..cubicTo(w * 0.67, h * 0.12, w * 0.83, h * 0.17, w * 0.83, h * 0.38)
      ..lineTo(w * 0.83, h * 0.88)
      ..close();
    canvas.drawPath(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = kGold.withValues(alpha: 0.75),
    );

    // Mihrab-Motiv (Gebetsnische) im Kopfbereich
    final mihrab = Path()
      ..moveTo(w * 0.30, h * 0.52)
      ..lineTo(w * 0.30, h * 0.36)
      ..cubicTo(w * 0.30, h * 0.22, w * 0.40, h * 0.19, w * 0.5, h * 0.19)
      ..cubicTo(w * 0.60, h * 0.19, w * 0.70, h * 0.22, w * 0.70, h * 0.36)
      ..lineTo(w * 0.70, h * 0.52)
      ..close();
    canvas.drawPath(
      mihrab,
      Paint()..color = Colors.white.withValues(alpha: 0.10),
    );
    canvas.drawPath(
      mihrab,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = kGold.withValues(alpha: 0.9),
    );

    // Kleine Kaaba in der Nische
    final cube = Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.365), width: w * 0.17, height: w * 0.17);
    canvas.drawRRect(
      RRect.fromRectAndRadius(cube, const Radius.circular(1.5)),
      Paint()..color = const Color(0xFF0C0C0C),
    );
    canvas.drawLine(
      Offset(cube.left, cube.top + cube.height * 0.34),
      Offset(cube.right, cube.top + cube.height * 0.34),
      Paint()
        ..color = kGold
        ..strokeWidth = 1.6,
    );

    // Mittellinie und Musterstriche im Fußbereich
    for (var i = 0; i < 3; i++) {
      final y = h * (0.62 + i * 0.09);
      canvas.drawLine(
        Offset(w * 0.26, y),
        Offset(w * 0.74, y),
        Paint()
          ..color = kGold.withValues(alpha: 0.35)
          ..strokeWidth = 1.0,
      );
    }

    // Fransen an der Fußseite
    for (var i = 0; i < 7; i++) {
      final x = w * (0.14 + i * 0.12);
      canvas.drawLine(
        Offset(x, h * 0.94),
        Offset(x, h * 0.99),
        Paint()
          ..color = kGold.withValues(alpha: 0.8)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );
    }

    // Richtungsspitze über der Kopfseite
    final tip = Path()
      ..moveTo(w * 0.5, -h * 0.035)
      ..lineTo(w * 0.42, h * 0.035)
      ..lineTo(w * 0.58, h * 0.035)
      ..close();
    canvas.drawPath(
      tip,
      Paint()..color = aligned ? const Color(0xFF1E9E6A) : kGold,
    );
  }

  @override
  bool shouldRepaint(covariant PrayerRugNeedlePainter old) => old.aligned != aligned;
}

// =============================================================================
//  10. Tab 3 — Tesbih / Tools
// =============================================================================

class TasbihTab extends StatelessWidget {
  const TasbihTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = appState.tasbihTarget;
    final count = appState.tasbihCount;
    final inRound = target > 0 ? count % target : count;
    final rounds = target > 0 ? count ~/ target : 0;
    final progress = target > 0 ? inRound / target : 0.0;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        PageHeader(title: tr('tasbih_title'), subtitle: tr('tasbih_tap')),
        const SizedBox(height: 8),

        // Dhikr-Auswahl
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: appState.dhikrList.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) => ChoiceChip(
              label: Text(appState.dhikrList[i]),
              selected: appState.dhikrIndex == i,
              onSelected: (_) => appState.setDhikrIndex(i),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Zähler
        Center(
          child: GestureDetector(
            onTap: appState.tasbihIncrement,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [kGreen, kDeep],
                ),
                boxShadow: [
                  BoxShadow(
                    color: kGreen.withValues(alpha: 0.35),
                    blurRadius: 26,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 220,
                    height: 220,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 6,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation(kGold),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(appState.currentDhikr,
                          style: const TextStyle(color: kGold, fontSize: 15)),
                      const SizedBox(height: 6),
                      Text('$inRound',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 64,
                              fontWeight: FontWeight.w300,
                              height: 1.0)),
                      const SizedBox(height: 4),
                      Text('${tr('tasbih_target')} $target · ×$rounds',
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 26),

        // Ziel & Reset
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final t in [33, 99, 100])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text('$t'),
                    selected: target == t,
                    onSelected: (_) => appState.setTasbihTarget(t),
                  ),
                ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: appState.tasbihReset,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(tr('tasbih_reset')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            '${tr('motivation')}: ${motivationOfTheDay(DateTime.now())}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
//  11. Tab 4 — Frage & Antwort (gesperrt)
// =============================================================================

class QaLockedTab extends StatelessWidget {
  const QaLockedTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        PageHeader(title: tr('tab_qa')),
        const SizedBox(height: 40),
        Center(
          child: Container(
            width: 116,
            height: 116,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.surfaceContainerHighest,
              border: Border.all(color: kGold.withValues(alpha: 0.6), width: 1.5),
            ),
            child: Icon(Icons.lock_outline, size: 50, color: kGold),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: kGold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              tr('coming_soon'),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700, color: kGold),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 34),
          child: Text(
            tr('qa_locked_body'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ),
        const SizedBox(height: 28),
        Center(
          child: Text('Kommt bald · Yakında · Coming soon',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
        ),
      ],
    );
  }
}

// =============================================================================
//  12. Tab 5 — Einstellungen
// =============================================================================

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        PageHeader(title: tr('tab_settings')),

        _section(context, tr('settings_language')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SegmentedButton<AppLang>(
            segments: const [
              ButtonSegment(value: AppLang.de, label: Text('Deutsch')),
              ButtonSegment(value: AppLang.tr, label: Text('Türkçe')),
              ButtonSegment(value: AppLang.en, label: Text('English')),
            ],
            selected: {appState.lang},
            onSelectionChanged: (s) => appState.setLang(s.first),
          ),
        ),

        _section(context, tr('settings_appearance')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(value: ThemeMode.system, label: Text(tr('theme_system'))),
              ButtonSegment(value: ThemeMode.light, label: Text(tr('theme_light'))),
              ButtonSegment(value: ThemeMode.dark, label: Text(tr('theme_dark'))),
            ],
            selected: {appState.themeMode},
            onSelectionChanged: (s) => appState.setTheme(s.first),
          ),
        ),
        SwitchListTile(
          value: appState.use24h,
          onChanged: appState.setUse24h,
          title: Text(tr('settings_time_format')),
          secondary: const Icon(Icons.access_time),
        ),

        _section(context, tr('settings_calculation')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.wb_sunny_outlined),
                  title: Text(tr('settings_madhab')),
                  subtitle: Text(appState.hanafiAsr
                      ? tr('madhab_hanafi')
                      : tr('madhab_shafii')),
                  trailing: Switch(
                    value: appState.hanafiAsr,
                    onChanged: (v) {
                      appState.setHanafiAsr(v);
                      if (appState.useDiyanetSync) appState.syncDiyanet();
                    },
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: appState.useDiyanetSync,
                  onChanged: (v) {
                    appState.setUseSync(v);
                    if (v) appState.syncDiyanet();
                  },
                  secondary: const Icon(Icons.cloud_sync_outlined),
                  title: Text(tr('settings_sync')),
                  subtitle: Text(tr('settings_sync_hint')),
                ),
                if (appState.useDiyanetSync) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(tr('last_sync')),
                    subtitle: Text(appState.lastSync == null
                        ? tr('never')
                        : '${longDate(appState.lastSync!)} · ${fmtTime(appState.lastSync!)}'),
                    trailing: appState.syncing
                        ? const SizedBox(
                            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : TextButton(
                            onPressed: () async {
                              final ok = await appState.syncDiyanet();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(ok ? tr('sync_ok') : tr('sync_failed')),
                                ));
                              }
                            },
                            child: Text(tr('sync_now')),
                          ),
                  ),
                ],
              ],
            ),
          ),
        ),

        _section(context, tr('settings_offsets')),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(tr('settings_offsets_hint'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Card(
            child: Column(
              children: [
                for (final p in P.values)
                  ListTile(
                    dense: true,
                    leading: Icon(p.icon, size: 20),
                    title: Text(p.label),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () =>
                              appState.setOffset(p, (appState.offsets[p] ?? 0) - 1),
                        ),
                        SizedBox(
                          width: 42,
                          child: Text(
                            '${(appState.offsets[p] ?? 0) > 0 ? '+' : ''}${appState.offsets[p] ?? 0}',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () =>
                              appState.setOffset(p, (appState.offsets[p] ?? 0) + 1),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),

        _section(context, tr('location')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Card(
            child: ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(appState.lat == null
                  ? tr('location_needed')
                  : '${appState.lat!.toStringAsFixed(4)}°, ${appState.lng!.toStringAsFixed(4)}°'),
              trailing: FilledButton.tonalIcon(
                onPressed: () => appState.refreshLocation(),
                icon: const Icon(Icons.my_location, size: 18),
                label: Text(tr('refresh_location')),
              ),
            ),
          ),
        ),

        _section(context, tr('settings_about')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(tr('about_body'),
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text('Nur Islam · 1.0.0',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
        ),
      ],
    );
  }

  Widget _section(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 10),
        child: Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      );
}
