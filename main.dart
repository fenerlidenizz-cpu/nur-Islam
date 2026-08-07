// =============================================================================
//  Nur Islam — main.dart  (Version 3)
//  Kostenlos · werbefrei · ohne Konto · offlinefähig · DE / TR / EN
//
//  Neu:
//   - Diyanet-Temkin: Öğle +5, İkindi +4 (einfaches Schattenmaß), Güneş −5, Akşam +7
//   - İmsak-/Yatsı-Winkel einstellbar + Kalibrierung nach eigener Referenz
//   - Umlaute und türkische Sonderzeichen korrekt
//   - Moscheen: nur sunnitische Gemeinden (abschaltbar)
//   - Gebets-Tracker mit Häkchen, Serie und Freundesvergleich (rein lokal)
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
import 'package:url_launcher/url_launcher.dart';

/// Link, den Freunde zum Installieren bekommen. Sobald die App im Play Store
/// ist, hier die Store-Adresse eintragen.
const String kAppShareUrl = 'https://github.com/';

final AppState appState = AppState();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appState.init();
  runApp(const NurIslamApp());
}

// =============================================================================
//  1. Farbwelten
// =============================================================================

enum AppPalette { indigo, iznik, plum }

class PaletteData {
  final String nameDe, nameTr, nameEn;
  final Color deep, surface, primary, gold, accent;
  const PaletteData(this.nameDe, this.nameTr, this.nameEn, this.deep,
      this.surface, this.primary, this.gold, this.accent);
}

const Map<AppPalette, PaletteData> palettes = {
  AppPalette.indigo: PaletteData(
    'Nacht-Indigo', 'Gece Lacivert', 'Midnight Indigo',
    Color(0xFF080F1F), Color(0xFF121C33), Color(0xFF1E3060),
    Color(0xFFD8B45A), Color(0xFF6E8CC7),
  ),
  AppPalette.iznik: PaletteData(
    'İznik-Türkis', 'İznik Turkuaz', 'Iznik Turquoise',
    Color(0xFF06181C), Color(0xFF0D2A30), Color(0xFF11525C),
    Color(0xFFDCB863), Color(0xFF3FB3B8),
  ),
  AppPalette.plum: PaletteData(
    'Aubergine', 'Patlıcan', 'Aubergine',
    Color(0xFF130F1B), Color(0xFF211A2D), Color(0xFF3D2C52),
    Color(0xFFC9A227), Color(0xFF9B7BC4),
  ),
};

PaletteData get pal => palettes[appState.palette]!;

ThemeData buildTheme(Brightness b, AppPalette p) {
  final d = palettes[p]!;
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: d.primary,
    brightness: b,
    primary: dark ? d.gold : d.primary,
    secondary: d.accent,
    surface: dark ? d.surface : Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? d.deep : const Color(0xFFF6F5F1),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: d.gold.withValues(alpha: dark ? 0.18 : 0.28)),
      ),
      color: dark ? d.surface : Colors.white,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? d.deep : Colors.white,
      indicatorColor: d.gold.withValues(alpha: 0.18),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 11, color: dark ? Colors.white70 : Colors.black87),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      isDense: true,
    ),
  );
}

// =============================================================================
//  2. Sprachen
// =============================================================================

enum AppLang { de, tr, en }

const Map<String, List<String>> _strings = {
  'tab_times': ['Zeiten', 'Vakitler', 'Times'],
  'tab_mosques': ['Moscheen', 'Camiler', 'Mosques'],
  'tab_qibla': ['Qibla', 'Kıble', 'Qibla'],
  'tab_tools': ['Tesbih', 'Tesbih', 'Tasbih'],
  'tab_more': ['Mehr', 'Daha', 'More'],
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
  'motivation': ['Motivation des Tages', 'Günün Motivasyonu', 'Daily Motivation'],

  'location': ['Standort', 'Konum', 'Location'],
  'location_loading': ['Standort wird ermittelt …', 'Konum alınıyor …', 'Getting location …'],
  'location_needed': [
    'Für Gebetszeiten und Qibla wird ein Standort benötigt.',
    'Namaz vakitleri ve kıble için konum gerekli.',
    'Prayer times and qibla need a location.',
  ],
  'location_denied': [
    'Standortfreigabe abgelehnt. Du kannst den Ort auch von Hand wählen.',
    'Konum izni reddedildi. Konumu elle de seçebilirsin.',
    'Location denied. You can also choose a place manually.',
  ],
  'location_denied_forever': [
    'Standortzugriff blockiert. Aktiviere ihn in den Systemeinstellungen oder wähle den Ort von Hand.',
    'Konum izni engellendi. Sistem ayarlarından aç veya konumu elle seç.',
    'Location blocked. Enable it in system settings or choose a place manually.',
  ],
  'location_service_off': ['Ortungsdienste sind ausgeschaltet.', 'Konum servisleri kapalı.', 'Location services are off.'],
  'allow_location': ['Standort freigeben', 'Konuma izin ver', 'Allow location'],
  'open_settings': ['Einstellungen öffnen', 'Ayarları aç', 'Open settings'],
  'refresh_location': ['Standort aktualisieren', 'Konumu güncelle', 'Refresh location'],
  'choose_manually': ['Ort selbst wählen', 'Konumu kendim seç', 'Choose place manually'],
  'retry': ['Erneut versuchen', 'Tekrar dene', 'Try again'],
  'loc_auto': ['Automatisch (GPS)', 'Otomatik (GPS)', 'Automatic (GPS)'],
  'loc_manual': ['Selbst gewählt', 'Elle seçilmiş', 'Chosen manually'],
  'search_place': ['Ort suchen', 'Yer ara', 'Search place'],
  'search_hint': ['z. B. Köln Ehrenfeld', 'örn. Köln Ehrenfeld', 'e.g. Cologne Ehrenfeld'],
  'searching': ['Wird gesucht …', 'Aranıyor …', 'Searching …'],
  'no_results': ['Nichts gefunden.', 'Sonuç yok.', 'Nothing found.'],
  'coords_manual': ['Koordinaten von Hand', 'Koordinatları elle gir', 'Coordinates by hand'],
  'latitude': ['Breitengrad', 'Enlem', 'Latitude'],
  'longitude': ['Längengrad', 'Boylam', 'Longitude'],
  'apply': ['Übernehmen', 'Uygula', 'Apply'],
  'open_in_maps': ['In Karten öffnen', 'Haritada aç', 'Open in maps'],
  'maps_tip': [
    'Tipp: In Google Maps lange auf eine Stelle tippen, die Koordinaten kopieren und hier einfügen.',
    'İpucu: Google Haritalar\'da bir noktaya uzun bas, koordinatları kopyalayıp buraya yapıştır.',
    'Tip: In Google Maps long-press a spot, copy the coordinates and paste them here.',
  ],

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
  'no_compass': ['Kein Magnetsensor vorhanden — nur Gradanzeige.', 'Manyetik sensör yok — sadece derece.', 'No magnetometer — degrees only.'],
  'calibrate_needed': ['Kompass ungenau — bitte kalibrieren.', 'Pusula hassas değil — kalibre et.', 'Compass inaccurate — please calibrate.'],

  'mosques_title': ['Moscheen in der Nähe', 'Yakındaki camiler', 'Mosques nearby'],
  'mosques_loading': ['Moscheen werden gesucht …', 'Camiler aranıyor …', 'Searching mosques …'],
  'mosques_none': [
    'Im gewählten Umkreis wurde nichts gefunden. Versuch einen größeren Radius.',
    'Seçilen yarıçapta bir şey bulunamadı. Daha geniş bir yarıçap dene.',
    'Nothing found in this radius. Try a larger one.',
  ],
  'mosques_offline': [
    'Für die Suche wird einmalig eine Internetverbindung benötigt. Gefundene Moscheen bleiben gespeichert.',
    'Arama için bir kez internet gerekir. Bulunan camiler kaydedilir.',
    'The search needs an internet connection once. Found mosques stay saved.',
  ],
  'mosques_source': [
    'Daten: OpenStreetMap-Mitwirkende (ODbL)',
    'Veri: OpenStreetMap katkıda bulunanlar (ODbL)',
    'Data: OpenStreetMap contributors (ODbL)',
  ],
  'mosques_times_note': [
    'Eigene Gebetszeiten einer Gemeinde zeigt die App nicht — dafür braucht es die Freigabe der jeweiligen Moschee.',
    'Bir cemaatin kendi vakitleri gösterilmiyor — bunun için caminin izni gerekir.',
    'A congregation\'s own timetable is not shown — that needs the mosque\'s consent.',
  ],
  'only_sunni': ['Nur sunnitische Gemeinden', 'Sadece Sünni cemaatler', 'Sunni congregations only'],
  'only_sunni_hint': [
    'Blendet Einträge aus, die in OpenStreetMap einer anderen Ausrichtung zugeordnet sind. '
        'Die Angaben stammen von OpenStreetMap und können unvollständig sein.',
    'OpenStreetMap\'te başka bir mezhebe atanmış kayıtları gizler. Bilgiler OpenStreetMap\'ten gelir ve eksik olabilir.',
    'Hides entries assigned to a different denomination in OpenStreetMap. The data comes from OpenStreetMap and may be incomplete.',
  ],
  'radius': ['Umkreis', 'Yarıçap', 'Radius'],
  'search_again': ['Neu suchen', 'Yeniden ara', 'Search again'],
  'set_reference': ['Als meine Moschee markieren', 'Camim olarak seç', 'Set as my mosque'],
  'my_mosque': ['Meine Moschee', 'Camim', 'My mosque'],

  'time_source': ['Zeitquelle', 'Vakit kaynağı', 'Time source'],
  'src_calc': ['Berechnung auf dem Gerät', 'Cihazda hesaplama', 'Calculated on device'],
  'src_calc_sub': ['Diyanet-Methode mit Temkin, funktioniert offline', 'Temkinli Diyanet yöntemi, çevrimdışı çalışır', 'Diyanet method with temkin, works offline'],
  'src_online': ['Online-Abgleich', 'Çevrimiçi eşitleme', 'Online sync'],
  'src_online_sub': ['Lädt den Monatskalender und speichert ihn offline', 'Aylık takvimi indirir ve çevrimdışı saklar', 'Downloads the monthly calendar and stores it offline'],
  'src_custom': ['Eigene Tabelle', 'Kendi tablom', 'My own table'],
  'src_custom_sub': ['Zeiten selbst einfügen — hat immer Vorrang', 'Vakitleri kendin gir — her zaman öncelikli', 'Enter times yourself — always takes priority'],
  'custom_table': ['Eigene Zeiten einfügen', 'Kendi vakitlerini gir', 'Paste your own times'],
  'custom_paste_hint': [
    'Kopiere die Monatstabelle deiner Quelle und füge sie hier ein. Erkannt wird jede Zeile mit '
        'einem Tag und sechs Uhrzeiten — in der Reihenfolge İmsak, Sonnenaufgang, Mittag, '
        'Nachmittag, Abend, Nacht.',
    'Kaynağındaki aylık tabloyu kopyalayıp buraya yapıştır. Bir gün ve altı saat içeren her satır tanınır — '
        'sıra: İmsak, Güneş, Öğle, İkindi, Akşam, Yatsı.',
    'Copy the monthly table from your source and paste it here. Any line with a day and six times is '
        'recognised — order: Fajr, Sunrise, Dhuhr, Asr, Maghrib, Isha.',
  ],
  'month': ['Monat', 'Ay', 'Month'],
  'year': ['Jahr', 'Yıl', 'Year'],
  'parsed_days': ['Erkannte Tage', 'Tanınan gün', 'Days recognised'],
  'save': ['Speichern', 'Kaydet', 'Save'],
  'saved': ['Gespeichert', 'Kaydedildi', 'Saved'],
  'nothing_parsed': ['Keine Zeile erkannt. Stimmt das Format?', 'Satır tanınmadı. Biçim doğru mu?', 'No line recognised. Is the format right?'],
  'stored_days': ['Gespeicherte Tage', 'Kayıtlı gün', 'Stored days'],
  'clear_table': ['Tabelle löschen', 'Tabloyu sil', 'Delete table'],
  'sync_now': ['Jetzt abgleichen', 'Şimdi eşitle', 'Sync now'],
  'sync_ok': ['Abgleich abgeschlossen', 'Eşitleme tamamlandı', 'Sync complete'],
  'sync_failed': ['Abgleich fehlgeschlagen — Berechnung bleibt aktiv.', 'Eşitleme başarısız — hesaplama geçerli.', 'Sync failed — calculation stays active.'],
  'last_sync': ['Letzter Abgleich', 'Son eşitleme', 'Last sync'],
  'never': ['Nie', 'Hiç', 'Never'],
  'source_local': ['Auf dem Gerät berechnet', 'Cihazda hesaplandı', 'Calculated on device'],
  'source_synced': ['Abgeglichen · offline gespeichert', 'Eşitlendi · çevrimdışı kayıtlı', 'Synced · stored offline'],
  'source_custom': ['Eigene Tabelle', 'Kendi tablom', 'My own table'],

  // Feineinstellung der Winkel
  'angles': ['Dämmerungswinkel', 'Şafak açıları', 'Twilight angles'],
  'angles_hint': [
    'Die Diyanet-Einstellung nutzt 14,9° und 13,9° — das entspricht den veröffentlichten '
        'Zeiten für Mitteleuropa. Die klassischen 18°/17° ergeben in nördlichen Breiten '
        'deutlich frühere İmsak- und spätere Yatsı-Zeiten. Weicht deine Moschee ab, '
        'kalibriere unten.',
    'Diyanet ayarı 14,9° ve 13,9° kullanır — Orta Avrupa için yayımlanan vakitlere uyar. '
        'Klasik 18°/17° kuzey enlemlerde çok daha erken İmsak ve geç Yatsı verir. '
        'Camin farklıysa aşağıdan kalibre et.',
    'The Diyanet setting uses 14.9° and 13.9°, matching the published times for central '
        'Europe. The classic 18°/17° gives much earlier Fajr and later Isha at northern '
        'latitudes. If your mosque differs, calibrate below.',
  ],
  'fajr_angle': ['İmsak-Winkel', 'İmsak açısı', 'Fajr angle'],
  'isha_angle': ['Yatsı-Winkel', 'Yatsı açısı', 'Isha angle'],
  'calibrate': ['Nach Referenz kalibrieren', 'Referansa göre kalibre et', 'Calibrate to reference'],
  'calibrate_hint': [
    'Trag die heutigen Zeiten deiner Referenz ein. Die App rechnet daraus den passenden Winkel '
        'aus und nutzt ihn für jeden weiteren Tag.',
    'Referansındaki bugünkü vakitleri gir. Uygulama uygun açıyı hesaplar ve her gün için kullanır.',
    'Enter today\'s times from your reference. The app derives the matching angle and uses it every day.',
  ],
  'calibrated': ['Kalibriert', 'Kalibre edildi', 'Calibrated'],
  'calibrate_failed': ['Zeit passt nicht zu diesem Standort.', 'Bu konuma uymuyor.', 'That time does not fit this location.'],
  'temkin': ['Temkin nach Diyanet', 'Diyanet temkini', 'Diyanet temkin'],
  'temkin_hint': [
    'Öğle +5, İkindi +4, Sonnenaufgang −5, Akşam +7 Minuten. Die Diyanet-Methode ergänzt '
        'Sonnenaufgang −1 und Akşam +1 über die Feinjustierung.',
    'Öğle +5, İkindi +4, Güneş −5, Akşam +7 dakika. Diyanet yöntemi ince ayarda ayrıca '
        'Güneş −1 ve Akşam +1 ekler.',
    'Dhuhr +5, Asr +4, sunrise −5, Maghrib +7 minutes. The Diyanet method adds sunrise −1 '
        'and Maghrib +1 through the fine tuning.',
  ],
  'asr_method': ['İkindi-Methode', 'İkindi yöntemi', 'Asr method'],
  'asr_first': ['Einfaches Schattenmaß (Diyanet)', 'Asr-ı evvel (Diyanet)', 'Single shadow (Diyanet)'],
  'asr_second': ['Doppeltes Schattenmaß (hanefitisch)', 'Asr-ı sânî (Hanefî)', 'Double shadow (Hanafi)'],

  'coming_soon': ['Kommt bald', 'Yakında', 'Coming soon'],
  'qa_locked_body': [
    'Frage & Antwort sowie Ayet- und Hadith-Inhalte werden vorbereitet und vor der Veröffentlichung '
        'auf ihre Quellen geprüft. Sie folgen in einem der nächsten Updates.',
    'Soru & Cevap ile ayet ve hadis içerikleri hazırlanıyor ve yayından önce kaynakları kontrol ediliyor.',
    'Q&A along with Qur\'an and hadith content is being prepared, with sources verified before release.',
  ],

  'tasbih_title': ['Tesbih', 'Tesbih', 'Tasbih'],
  'tasbih_target': ['Ziel', 'Hedef', 'Target'],
  'tasbih_reset': ['Zurücksetzen', 'Sıfırla', 'Reset'],
  'tasbih_tap': ['Zum Zählen tippen', 'Saymak için dokun', 'Tap to count'],

  // Tracker & Freunde
  'tracker': ['Gebete festhalten', 'Namaz takibi', 'Prayer tracker'],
  'tracker_today': ['Heute gebetet', 'Bugün kılınan', 'Prayed today'],
  'streak': ['Serie', 'Seri', 'Streak'],
  'days': ['Tage', 'gün', 'days'],
  'week': ['Letzte 7 Tage', 'Son 7 gün', 'Last 7 days'],
  'friends': ['Freunde', 'Arkadaşlar', 'Friends'],
  'friends_none': [
    'Noch keine Freunde hinzugefügt. Lade jemanden ein und tauscht euren Stand aus.',
    'Henüz arkadaş yok. Birini davet et ve durumunuzu paylaşın.',
    'No friends yet. Invite someone and exchange your progress.',
  ],
  'invite_friend': ['Freund einladen', 'Arkadaş davet et', 'Invite a friend'],
  'share_progress': ['Meinen Stand teilen', 'Durumumu paylaş', 'Share my progress'],
  'add_friend': ['Stand eines Freundes einfügen', 'Arkadaşın durumunu ekle', 'Paste a friend\'s progress'],
  'paste_code_hint': [
    'Füge hier den Code ein, den dein Freund dir geschickt hat.',
    'Arkadaşının gönderdiği kodu buraya yapıştır.',
    'Paste the code your friend sent you here.',
  ],
  'copied': ['In die Zwischenablage kopiert', 'Panoya kopyalandı', 'Copied to clipboard'],
  'code_invalid': ['Der Code konnte nicht gelesen werden.', 'Kod okunamadı.', 'The code could not be read.'],
  'your_name': ['Dein Name', 'Adın', 'Your name'],
  'name_hint': ['Wird nur in dem Code angezeigt, den du teilst.', 'Sadece paylaştığın kodda görünür.', 'Only shown in the code you share.'],
  'remove': ['Entfernen', 'Kaldır', 'Remove'],
  'me': ['Ich', 'Ben', 'Me'],
  'no_server_note': [
    'Alles bleibt auf deinem Gerät. Es gibt kein Konto und keinen Server — der Vergleich '
        'entsteht nur aus den Codes, die ihr euch gegenseitig schickt.',
    'Her şey cihazında kalır. Hesap ve sunucu yok — karşılaştırma sadece birbirinize '
        'gönderdiğiniz kodlardan oluşur.',
    'Everything stays on your device. There is no account and no server — the comparison is '
        'built only from the codes you send each other.',
  ],

  'settings_language': ['Sprache', 'Dil', 'Language'],
  'settings_appearance': ['Darstellung', 'Görünüm', 'Appearance'],
  'settings_palette': ['Farbwelt', 'Renk dünyası', 'Colour theme'],
  'theme_system': ['System', 'Sistem', 'System'],
  'theme_light': ['Hell', 'Açık', 'Light'],
  'theme_dark': ['Dunkel', 'Koyu', 'Dark'],
  'settings_calculation': ['Berechnung', 'Hesaplama', 'Calculation'],
  'settings_offsets': ['Feinjustierung (± Minuten)', 'İnce ayar (± dakika)', 'Fine tuning (± minutes)'],
  'settings_offsets_hint': [
    'Nur nutzen, wenn deine Moschee bewusst abweichende Zeiten ansagt.',
    'Sadece camin farklı vakit okuyorsa kullan.',
    'Only use this if your mosque announces different times on purpose.',
  ],
  'settings_time_format': ['24-Stunden-Format', '24 saat biçimi', '24-hour format'],
  'settings_about': ['Über uns', 'Hakkımızda', 'About us'],
  'about_body': [
    'Einfach nur ein Akh, der zusammen mit Claude versucht, die Welt ein kleines bisschen besser '
        'zu machen. Nur Islam ist und bleibt kostenlos, ohne Werbung, ohne Konto und ohne '
        'Datensammeln. Alles, was du hier eingibst, bleibt auf deinem Gerät.',
    'Sadece dünyayı biraz daha güzel yapmak isteyen bir kardeşiniz — Claude ile birlikte. '
        'Nur Islam ücretsizdir ve öyle kalacak: reklamsız, hesapsız, veri toplamadan. '
        'Girdiğin her şey cihazında kalır.',
    'Just an akh trying, together with Claude, to make the world a little better. Nur Islam is '
        'and stays free — no ads, no account, no data collection. Everything you enter stays on '
        'your device.',
  ],
  'km': ['km', 'km', 'km'],

  // Tagesnavigation
  'today_button': ['Heute', 'Bugün', 'Today'],
  'pick_day': ['Tag wählen', 'Gün seç', 'Pick a day'],
  'swipe_hint': ['Wischen für andere Tage', 'Diğer günler için kaydır', 'Swipe for other days'],

  // Moschee als Zeitquelle
  'src_calc_short': ['Berechnet', 'Hesaplanan', 'Calculated'],
  'times_from': ['Zeiten von', 'Vakitler', 'Times from'],
  'mosque_info': ['Moschee-Infos', 'Cami bilgileri', 'Mosque info'],
  'call': ['Anrufen', 'Ara', 'Call'],
  'route': ['Wegbeschreibung', 'Yol tarifi', 'Directions'],
  'website': ['Webseite', 'Web sitesi', 'Website'],
  'opening_hours': ['Öffnungszeiten', 'Açılış saatleri', 'Opening hours'],
  'no_info': ['Keine Angabe in OpenStreetMap', 'OpenStreetMap\'te bilgi yok', 'Not recorded in OpenStreetMap'],
  'use_this_mosque': ['Zeiten dieser Moschee übernehmen', 'Bu caminin vakitlerini kullan', 'Use this mosque\'s times'],
  'change_mosque': ['Moschee wechseln', 'Cami değiştir', 'Change mosque'],
  'clear_mosque': ['Keine Moschee — eigener Standort', 'Cami yok — kendi konumum', 'No mosque — my own location'],
  'mosque_active': ['Zeiten beziehen sich auf diese Moschee', 'Vakitler bu camiye göre', 'Times are based on this mosque'],
  'mosque_times_explain': [
    'Die Zeiten werden für die Koordinaten dieser Moschee gerechnet. Die Gemeinde kann '
        'für das Gemeinschaftsgebet abweichende Zeiten ansagen — die kannst du unter '
        '„Eigene Zeiten einfügen" hinterlegen.',
    'Vakitler bu caminin koordinatlarına göre hesaplanır. Cemaat, cemaatle namaz için farklı '
        'vakit okuyabilir — bunları „Kendi vakitlerini gir" bölümüne yazabilirsin.',
    'Times are calculated for this mosque\'s coordinates. The congregation may announce '
        'different times for the congregational prayer — you can enter those under '
        '„Paste your own times".',
  ],
  'enter_jamaat': ['Zeiten dieser Moschee eintragen', 'Bu caminin vakitlerini gir', 'Enter this mosque\'s times'],

  // Kerahat
  'kerahat': ['Kerahat-Zeiten', 'Kerahat vakitleri', 'Makruh times'],
  'kerahat_show': ['Kerahat-Zeiten anzeigen', 'Kerahat vakitlerini göster', 'Show makruh times'],
  'kerahat_hint': [
    'Zeiten, in denen das Gebet als unerwünscht gilt: nach dem Sonnenaufgang, kurz vor dem '
        'Mittag und vor dem Sonnenuntergang. Die Längen kannst du an deine Moschee anpassen.',
    'Namazın mekruh sayıldığı vakitler: güneş doğduktan sonra, öğleden hemen önce ve '
        'güneş batmadan önce. Süreleri camine göre ayarlayabilirsin.',
    'Times when prayer is considered disliked: after sunrise, shortly before noon and before '
        'sunset. You can adjust the durations to match your mosque.',
  ],
  'k_israk': ['Nach Sonnenaufgang', 'Güneş doğduktan sonra', 'After sunrise'],
  'k_istiva': ['Mittagsstand', 'İstiva', 'Solar noon'],
  'k_isfirar': ['Vor Sonnenuntergang', 'Güneş batmadan önce', 'Before sunset'],
  'kerahat_in': ['bis Kerahat', 'Kerahat\'a', 'until makruh time'],
  'kerahat_now': ['Kerahat-Zeit läuft', 'Kerahat vakti', 'Makruh time'],
  'kerahat_ends': ['endet in', 'bitiyor', 'ends in'],
  'minutes': ['Minuten', 'dakika', 'minutes'],

  // Community
  'tab_community': ['Community', 'Topluluk', 'Community'],
  'sub_news': ['Neuigkeiten', 'Haberler', 'News'],
  'sub_friends': ['Freunde', 'Arkadaşlar', 'Friends'],
  'sub_qa': ['Frage & Antwort', 'Soru & Cevap', 'Q&A'],
  'news_locked': [
    'Hier erscheinen bald Spendenaktionen und Nachrichten, die für die Gemeinschaft '
        'wichtig sind. Der Bereich wird erst freigeschaltet, wenn die Quellen dafür stehen.',
    'Burada yakında bağış kampanyaları ve topluluk için önemli haberler görünecek. '
        'Kaynaklar hazır olduğunda açılacak.',
    'Donation campaigns and news that matter to the community will appear here. The '
        'section unlocks once the sources are in place.',
  ],
  'avg_week': ['Schnitt pro Woche', 'Haftalık ortalama', 'Weekly average'],
  'avg_month': ['Schnitt pro Monat', 'Aylık ortalama', 'Monthly average'],
  'per_day': ['pro Tag', 'günde', 'per day'],
  'ranking': ['Rangliste', 'Sıralama', 'Ranking'],
  'total_prayers': ['Gebete', 'namaz', 'prayers'],
  'my_code': ['Mein Code', 'Kodum', 'My code'],
  'my_code_hint': [
    'Schick diesen Code deinen Freunden. Sie fügen ihn bei sich ein — und du ihren.',
    'Bu kodu arkadaşlarına gönder. Onlar sana kendi kodlarını yollasın.',
    'Send this code to your friends. They paste it on their side — and you paste theirs.',
  ],

  // Kalender
  'calendar': ['Kalender', 'Takvim', 'Calendar'],
  'special_days': ['Besondere Tage', 'Özel günler', 'Special days'],
  'hijri_note': [
    'Die islamischen Daten sind berechnet und können um einen Tag abweichen. '
        'Maßgeblich ist der Kalender deiner Moschee.',
    'Hicri tarihler hesaplanmıştır ve bir gün sapabilir. Esas olan camindeki takvimdir.',
    'Islamic dates are calculated and may differ by a day. Your mosque\'s calendar is authoritative.',
  ],

  // Tutorial
  'skip': ['Überspringen', 'Atla', 'Skip'],
  'next': ['Weiter', 'Devam', 'Next'],
  'start': ['Los geht\'s', 'Başla', 'Let\'s go'],
  'tut1_t': ['Willkommen', 'Hoş geldin', 'Welcome'],
  'tut1_b': [
    'Nur Islam zeigt dir Gebetszeiten, die Qibla-Richtung und mehr — kostenlos, '
        'ohne Werbung und ohne Konto.',
    'Nur Islam sana namaz vakitlerini, kıble yönünü ve daha fazlasını gösterir — '
        'ücretsiz, reklamsız ve hesapsız.',
    'Nur Islam shows prayer times, the qibla direction and more — free, without ads '
        'and without an account.',
  ],
  'tut2_t': ['Tage wechseln', 'Günleri değiştir', 'Switch days'],
  'tut2_b': [
    'Wische auf dem Zeiten-Reiter nach links oder rechts, um einen Tag vor oder zurück '
        'zu gehen. Über das Kalender-Symbol kommst du zu jedem Datum.',
    'Vakitler sekmesinde sola veya sağa kaydırarak gün değiştirebilirsin. Takvim '
        'simgesiyle istediğin tarihe gidebilirsin.',
    'Swipe left or right on the times tab to move a day forward or back. The calendar '
        'icon takes you to any date.',
  ],
  'tut3_t': ['Zeiten deiner Moschee', 'Caminin vakitleri', 'Your mosque\'s times'],
  'tut3_b': [
    'Oben rechts steht, woher die Zeiten stammen. Tippe darauf, um eine Moschee zu '
        'wählen, sie anzurufen oder den Weg dorthin zu öffnen.',
    'Sağ üstte vakitlerin kaynağı yazar. Dokunarak cami seçebilir, arayabilir veya '
        'yol tarifi açabilirsin.',
    'The top right shows where the times come from. Tap it to choose a mosque, call it '
        'or open directions.',
  ],
  'tut4_t': ['Qibla finden', 'Kıbleyi bul', 'Find the qibla'],
  'tut4_b': [
    'Halte das Gerät flach. Der Ring leuchtet heller, je näher du an der Richtung bist, '
        'und der Teppich zeigt mit der Kopfseite zur Kaaba.',
    'Cihazı düz tut. Yöne yaklaştıkça halka daha parlak yanar; seccadenin baş tarafı '
        'Kâbe\'yi gösterir.',
    'Hold the device flat. The ring glows brighter as you get closer, and the rug\'s head '
        'end points to the Kaaba.',
  ],
  'tut5_t': ['Festhalten und teilen', 'Takip et ve paylaş', 'Track and share'],
  'tut5_b': [
    'Hake verrichtete Gebete ab und vergleiche dich mit Freunden — alles bleibt auf '
        'deinem Gerät, es gibt kein Konto und keinen Server.',
    'Kıldığın namazları işaretle ve arkadaşlarınla karşılaştır — her şey cihazında '
        'kalır, hesap ve sunucu yok.',
    'Tick off the prayers you have performed and compare with friends — everything stays '
        'on your device, with no account and no server.',
  ],

  // Tesbih
  'target_reached': ['Ziel erreicht', 'Hedefe ulaşıldı', 'Target reached'],
  'sub_meet': ['Verabreden', 'Buluşma', 'Meet up'],
  'meet_locked': [
    'Bald könnt ihr euch hier zum gemeinsamen Gebet verabreden: eine Moschee und eine '
        'Zeit vorschlagen, abstimmen, zu- oder absagen. Der Vorschlag mit den meisten '
        'Stimmen steht oben.',
    'Yakında burada cemaatle namaz için buluşma ayarlayabileceksiniz: bir cami ve saat '
        'öner, oy ver, katıl ya da iptal et. En çok oy alan öneri en üstte olur.',
    'Soon you will be able to arrange congregational prayer here: propose a mosque and a '
        'time, vote, accept or decline. The proposal with the most votes stays on top.',
  ],
  'notifications': ['Benachrichtigungen', 'Bildirimler', 'Notifications'],
  'notifications_locked': [
    'Erinnerungen zu den Gebetszeiten folgen im nächsten Update.',
    'Namaz vakti hatırlatmaları bir sonraki güncellemede geliyor.',
    'Prayer time reminders are coming in the next update.',
  ],
  'widgets': ['Startbildschirm-Widgets', 'Ana ekran widget\'ları', 'Home screen widgets'],
  'widget_alpha': ['Transparenz', 'Şeffaflık', 'Transparency'],
  'widget_hint': [
    'Lege ein Widget an, indem du lange auf eine freie Stelle deines Startbildschirms '
        'tippst und unter „Widgets" nach Nur Islam suchst. Es gibt ein breites Feld mit '
        'den Tageszeiten und einen Qibla-Kompass.',
    'Ana ekranda boş bir yere uzun basıp „Widget\'lar" altında Nur Islam\'ı ara. Günün '
        'vakitlerini gösteren geniş bir alan ve bir kıble pusulası var.',
    'Add a widget by long-pressing an empty spot on your home screen and looking for Nur '
        'Islam under „Widgets". There is a wide field with the day\'s times and a qibla compass.',
  ],
  'widget_refresh_note': [
    'Android erneuert Widgets höchstens alle 30 Minuten. Der Qibla-Kompass zeigt deshalb '
        'die feste Richtung zur Kaaba und dreht sich nicht mit dem Gerät — dafür öffne die App.',
    'Android widget\'ları en fazla 30 dakikada bir yeniler. Bu yüzden kıble pusulası sabit '
        'yönü gösterir, cihazla dönmez — bunun için uygulamayı aç.',
    'Android refreshes widgets at most every 30 minutes. The qibla compass therefore shows '
        'the fixed direction to the Kaaba and does not turn with the device — open the app for that.',
  ],
  'unlimited': ['Unbegrenzt', 'Sınırsız', 'Unlimited'],
  'method': ['Berechnungsmethode', 'Hesaplama yöntemi', 'Calculation method'],
  'method_custom': ['Eigene Einstellung', 'Kendi ayarım', 'Custom'],
  'method_hint': [
    'Die Methode legt die Winkel für İmsak und Yatsı fest sowie die Art der '
        'İkindi-Berechnung. Diyanet ist die Voreinstellung.',
    'Yöntem, İmsak ve Yatsı açılarını ve İkindi hesabını belirler. Varsayılan Diyanet\'tir.',
    'The method sets the twilight angles for Fajr and Isha and how Asr is calculated. '
        'Diyanet is the default.',
  ],
  'isha_interval': ['Yatsı als fester Abstand', 'Yatsı sabit aralık', 'Isha as fixed interval'],
  'after_maghrib': ['nach Akşam', 'akşamdan sonra', 'after Maghrib'],
  'code_length_note': [
    'Der Code enthält deinen Namen und die Zahlen der letzten 30 Tage. Kürzer als etwa '
        '20 Zeichen geht es nicht, solange es keinen Server gibt, auf dem die Daten liegen.',
    'Kod, adını ve son 30 günün sayılarını içerir. Verilerin durduğu bir sunucu olmadan '
        '20 karakterin altına inmek mümkün değil.',
    'The code carries your name and the counts of the last 30 days. It cannot get much '
        'below 20 characters as long as there is no server holding the data.',
  ],
  'name_needed': [
    'Trag zuerst deinen Namen ein — er wird bei deinen Freunden angezeigt.',
    'Önce adını gir — arkadaşlarında bu görünecek.',
    'Enter your name first — it is what your friends will see.',
  ],
  'tap_anywhere': [
    'Tippe auf die Perlen oder in das untere Drittel des Bildschirms',
    'Boncuklara veya ekranın alt üçte birine dokun',
    'Tap the beads or the lower third of the screen',
  ],
  'zakat_calculator': ['Zakat-Rechner', 'Zekat Hesaplayici', 'Zakat calculator'],
  'zakat_intro': [
    'Berechne, wie viel Zakat (Pflichtabgabe) du dieses Jahr zahlen musst. Alle Angaben bleiben nur auf deinem Geraet.',
    'Bu yil ne kadar zekat (farz bagis) odemen gerektigini hesapla. Tum veriler yalnizca cihazinda kalir.',
    'Calculate how much Zakat (obligatory almsgiving) you owe this year. All figures stay only on your device.',
  ],
  'zakat_cash': ['Bargeld & Bankguthaben', 'Nakit ve banka bakiyesi', 'Cash & bank balance'],
  'zakat_gold_grams': ['Gold (Gramm)', 'Altin (gram)', 'Gold (grams)'],
  'zakat_gold_price': ['Goldpreis pro Gramm', 'Gram altin fiyati', 'Gold price per gram'],
  'zakat_silver_grams': ['Silber (Gramm)', 'Gumus (gram)', 'Silver (grams)'],
  'zakat_silver_price': ['Silberpreis pro Gramm', 'Gram gumus fiyati', 'Silver price per gram'],
  'zakat_other_assets': ['Geschaeftsvermoegen & Sonstiges', 'Ticari mal ve diger varliklar', 'Business assets & other'],
  'zakat_debts': ['Kurzfristige Schulden', 'Kisa vadeli borclar', 'Short-term debts'],
  'zakat_nisab_basis': ['Nisab-Grenze berechnen nach', 'Nisap sinirini hesapla', 'Calculate Nisab threshold using'],
  'zakat_basis_gold': ['Gold (85 g)', 'Altin (85 g)', 'Gold (85 g)'],
  'zakat_basis_silver': ['Silber (595 g)', 'Gumus (595 g)', 'Silver (595 g)'],
  'zakat_total_assets': ['Zakatfaehiges Vermoegen', 'Zekata tabi varlik', 'Zakatable assets'],
  'zakat_nisab_value': ['Nisab-Grenze', 'Nisap siniri', 'Nisab threshold'],
  'zakat_result_due': ['Faelliger Zakat (2,5%)', 'Odenecek zekat (%2,5)', 'Zakat due (2.5%)'],
  'zakat_result_not_due': [
    'Dein Vermoegen liegt unter der Nisab-Grenze - kein Zakat faellig.',
    'Varligin nisap sinirinin altinda - zekat farz degil.',
    'Your assets are below the Nisab threshold - no Zakat is due.',
  ],
  'zakat_disclaimer': [
    'Ersetzt keine verbindliche Fiqh-Beratung. Preise bitte selbst aktuell halten.',
    'Baglayici bir fikih goruesunun yerini tutmaz. Fiyatlari guencel tutman gerekir.',
    'Not a substitute for binding religious guidance. Please keep prices up to date.',
  ],
  'fasting_tracker': ['Fasten-Tracker', 'Oruç Takibi', 'Fasting tracker'],
  'fasting_intro': [
    'Halte Pflicht- und freiwillige Fastentage fest – Ramadan, Montag/Donnerstag oder Ayyam al-Bid. Alles bleibt nur auf deinem Gerät.',
    'Farz ve nafile oruç günlerini kaydet – Ramazan, Pazartesi/Perşembe veya Eyyam-ı Bid. Her şey sadece cihazında kalır.',
    'Track obligatory and voluntary fasting days – Ramadan, Monday/Thursday or Ayyam al-Bid. Everything stays only on your device.',
  ],
  'fasting_today': ['Heute gefastet', 'Bugün oruçluyum', 'Fasted today'],
  'fasting_streak': ['Aktuelle Serie', 'Güncel seri', 'Current streak'],
  'fasting_days_suffix': ['Tage', 'gün', 'days'],
  'fasting_month_count': ['Diesen Monat', 'Bu ay', 'This month'],
  'fasting_last_days': ['Letzte Tage', 'Son günler', 'Recent days'],
};

String tr(String key) {
  final v = _strings[key];
  return v == null ? key : v[appState.lang.index];
}

const Map<AppLang, List<String>> _weekdays = {
  AppLang.de: ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'],
  AppLang.tr: ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'],
  AppLang.en: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'],
};

const Map<AppLang, List<String>> _weekdaysShort = {
  AppLang.de: ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'],
  AppLang.tr: ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'],
  AppLang.en: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
};

const Map<AppLang, List<String>> _months = {
  AppLang.de: ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'],
  AppLang.tr: ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'],
  AppLang.en: ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'],
};

const Map<AppLang, List<String>> _cardinals = {
  AppLang.de: ['N', 'NO', 'O', 'SO', 'S', 'SW', 'W', 'NW'],
  AppLang.tr: ['K', 'KD', 'D', 'GD', 'G', 'GB', 'B', 'KB'],
  AppLang.en: ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'],
};

String cardinalOf(double bearing) =>
    _cardinals[appState.lang]![((((bearing % 360) + 22.5) ~/ 45) % 8)];

String longDate(DateTime d) {
  final wd = _weekdays[appState.lang]![d.weekday - 1];
  final mo = _months[appState.lang]![d.month - 1];
  return appState.lang == AppLang.tr ? '${d.day} $mo $wd' : '$wd, ${d.day}. $mo ${d.year}';
}

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
  return list[date.difference(DateTime(date.year, 1, 1)).inDays % list.length];
}

// =============================================================================
//  3. Modelle
// =============================================================================

enum P { fajr, sunrise, dhuhr, asr, maghrib, isha }

extension PLabel on P {
  String get label => tr('p_$name');
  bool get isPrayer => this != P.sunrise;
  IconData get icon => switch (this) {
        P.fajr => Icons.nightlight_round,
        P.sunrise => Icons.wb_twilight,
        P.dhuhr => Icons.light_mode,
        P.asr => Icons.wb_sunny_outlined,
        P.maghrib => Icons.wb_twilight_outlined,
        P.isha => Icons.dark_mode_outlined,
      };
}

const List<P> kPrayers = [P.fajr, P.dhuhr, P.asr, P.maghrib, P.isha];

enum TimeSource { calculated, online, custom }

/// Bekannte Berechnungsverfahren. asr 1 = einfaches Schattenmaß, 2 = doppeltes.
class CalcMethod {
  final String id, name;
  final double fajr, isha;
  final int ishaInterval; // Minuten nach Akşam; 0 = Winkel verwenden
  final int asr;
  final bool temkin;
  final int offsetSunrise, offsetMaghrib;
  const CalcMethod(this.id, this.name, this.fajr, this.isha,
      {this.ishaInterval = 0,
      this.asr = 1,
      this.temkin = false,
      this.offsetSunrise = 0,
      this.offsetMaghrib = 0});
}

const List<CalcMethod> kMethods = [
  // Auf die veroeffentlichten Diyanet-Zeiten fuer Mitteleuropa abgeglichen.
  CalcMethod('diyanet', 'Diyanet İşleri Başkanlığı', 14.9, 13.9,
      asr: 1, temkin: true, offsetSunrise: -1, offsetMaghrib: 1),
  CalcMethod('mwl', 'Muslim World League', 18, 17),
  CalcMethod('isna', 'ISNA (Nordamerika)', 15, 15),
  CalcMethod('egypt', 'Ägyptische Vermessungsbehörde', 19.5, 17.5),
  CalcMethod('karachi', 'Karachi (Univ. of Islamic Sciences)', 18, 18),
  CalcMethod('ummalqura', 'Umm al-Qura (Mekka)', 18.5, 0, ishaInterval: 90),
  CalcMethod('dubai', 'Dubai', 18.2, 18.2),
  CalcMethod('tehran', 'Teheran', 17.7, 14),
  CalcMethod('france', 'UOIF Frankreich', 12, 12),
  CalcMethod('hanafi_mwl', 'Muslim World League (hanefitisch)', 18, 17, asr: 2),
];

enum LocState { unknown, loading, ready, serviceOff, denied, deniedForever, error }

class DayTimes {
  final DateTime date;
  final Map<P, DateTime> times;
  final TimeSource source;
  const DayTimes({required this.date, required this.times, required this.source});
  DateTime? operator [](P p) => times[p];
}

class Mosque {
  final String name;
  final double lat, lng;
  final String? street, city, denomination, phone, website, openingHours;
  const Mosque({
    required this.name,
    required this.lat,
    required this.lng,
    this.street,
    this.city,
    this.denomination,
    this.phone,
    this.website,
    this.openingHours,
  });

  String get address => [street, city].whereType<String>().where((s) => s.isNotEmpty).join(', ');

  Map<String, dynamic> toJson() => {
        'n': name, 'la': lat, 'lo': lng, 's': street, 'c': city,
        'd': denomination, 'p': phone, 'w': website, 'o': openingHours,
      };

  factory Mosque.fromJson(Map<String, dynamic> j) => Mosque(
        name: j['n'] as String,
        lat: (j['la'] as num).toDouble(),
        lng: (j['lo'] as num).toDouble(),
        street: j['s'] as String?,
        city: j['c'] as String?,
        denomination: j['d'] as String?,
        phone: j['p'] as String?,
        website: j['w'] as String?,
        openingHours: j['o'] as String?,
      );
}

extension FriendStats on Friend {
  int totalOver(int days) {
    final today = DateTime.now();
    var sum = 0;
    for (var i = 0; i < days; i++) {
      final d = today.subtract(Duration(days: i));
      final key = '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      sum += days == 0 ? 0 : (this.days[key] ?? 0);
    }
    return sum;
  }

  double averageOver(int days) => days == 0 ? 0 : totalOver(days) / days;
}

class Friend {
  final String name;
  /// Schlüssel: Tagesdatum, Wert: Anzahl verrichteter Gebete (0–5)
  final Map<String, int> days;
  final DateTime updated;
  const Friend({required this.name, required this.days, required this.updated});

  Map<String, dynamic> toJson() =>
      {'n': name, 'd': days, 'u': updated.millisecondsSinceEpoch};

  factory Friend.fromJson(Map<String, dynamic> j) => Friend(
        name: j['n'] as String,
        days: (j['d'] as Map).map((k, v) => MapEntry(k as String, (v as num).toInt())),
        updated: DateTime.fromMillisecondsSinceEpoch((j['u'] as num).toInt()),
      );
}

// =============================================================================
//  4. Berechnung nach Diyanet-Methode
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
  final double declination, equationOfTime;
  const _SunPos(this.declination, this.equationOfTime);
}

class PrayerCalculator {
  static const double sunriseAngle = 0.833;

  // Temkin nach Diyanet (Minuten)
  static const int temkinSunrise = -5;
  static const int temkinDhuhr = 5;
  static const int temkinAsr = 4;
  static const int temkinMaghrib = 7;

  static double julianDay(int year, int month, int day) {
    if (month <= 2) {
      year -= 1;
      month += 12;
    }
    final a = (year / 100).floor();
    final b = 2 - a + (a / 4).floor();
    return (365.25 * (year + 4716)).floor().toDouble() +
        (30.6001 * (month + 1)).floor().toDouble() +
        day + b - 1524.5;
  }

  static _SunPos sunPosition(double jd) {
    final d = jd - 2451545.0;
    final g = _fixAngle(357.529 + 0.98560028 * d);
    final q = _fixAngle(280.459 + 0.98564736 * d);
    final l = _fixAngle(q + 1.915 * _dsin(g) + 0.020 * _dsin(2 * g));
    final e = 23.439 - 0.00000036 * d;
    final ra = _fixHour(_datan2(_dcos(e) * _dsin(l), _dcos(l)) / 15);
    return _SunPos(_dasin(_dsin(e) * _dsin(l)), q / 15 - ra);
  }

  static double _midDay(double jd, double t) =>
      _fixHour(12 - sunPosition(jd + t).equationOfTime);

  static double _sunAngleTime(double jd, double t, double angle, double lat,
      {bool beforeNoon = false}) {
    final decl = sunPosition(jd + t).declination;
    final v = (-_dsin(angle) - _dsin(decl) * _dsin(lat)) / (_dcos(decl) * _dcos(lat));
    if (v.isNaN || v.abs() > 1) return double.nan;
    final ha = _dacos(v) / 15;
    final noon = _midDay(jd, t);
    return beforeNoon ? noon - ha : noon + ha;
  }

  static double _asrTime(double jd, double t, int shadowFactor, double lat) {
    final decl = sunPosition(jd + t).declination;
    return _sunAngleTime(jd, t, -_dacot(shadowFactor + _dtan((lat - decl).abs())), lat);
  }

  /// Sonnenhöhe zu einem konkreten Zeitpunkt — Grundlage der Kalibrierung.
  static double altitudeAt(DateTime local, double lat, double lng) {
    final day = DateTime(local.year, local.month, local.day);
    final tzHours = day.timeZoneOffset.inMinutes / 60.0;
    final jd = julianDay(day.year, day.month, day.day) - lng / (15 * 24);
    final localHours = local.hour + local.minute / 60.0;
    final t = (localHours - tzHours + lng / 15) / 24;
    final sp = sunPosition(jd + t);
    final noon = _midDay(jd, t);
    final ha = ((localHours - tzHours + lng / 15) - noon) * 15;
    final sinAlt = _dsin(lat) * _dsin(sp.declination) +
        _dcos(lat) * _dcos(sp.declination) * _dcos(ha);
    return _dasin(sinAlt.clamp(-1.0, 1.0));
  }

  static DayTimes compute({
    required DateTime date,
    required double lat,
    required double lng,
    required int shadowFactor,
    required double fajrAngle,
    required double ishaAngle,
    required bool useTemkin,
    int ishaIntervalMin = 0,
    Map<P, int> offsets = const {},
  }) {
    final day = DateTime(date.year, date.month, date.day);
    final tzHours = day.timeZoneOffset.inMinutes / 60.0;
    final jd = julianDay(day.year, day.month, day.day) - lng / (15 * 24);

    var tFajr = 5 / 24, tSunrise = 6 / 24, tDhuhr = 12 / 24;
    var tAsr = 13 / 24, tMaghrib = 18 / 24, tIsha = 18 / 24;

    for (var i = 0; i < 3; i++) {
      tFajr = _sunAngleTime(jd, tFajr, fajrAngle, lat, beforeNoon: true) / 24;
      tSunrise = _sunAngleTime(jd, tSunrise, sunriseAngle, lat, beforeNoon: true) / 24;
      tDhuhr = _midDay(jd, tDhuhr) / 24;
      tAsr = _asrTime(jd, tAsr, shadowFactor, lat) / 24;
      tMaghrib = _sunAngleTime(jd, tMaghrib, sunriseAngle, lat) / 24;
      tIsha = _sunAngleTime(jd, tIsha, ishaAngle, lat) / 24;
      if (tFajr.isNaN) tFajr = 4 / 24;
      if (tIsha.isNaN) tIsha = 22 / 24;
    }

    DateTime? toLocal(double tDays, P key, int temkin) {
      final hours = tDays * 24;
      if (hours.isNaN) return null;
      final minutes = ((hours + tzHours - lng / 15) * 60).round() +
          (useTemkin ? temkin : 0) +
          (offsets[key] ?? 0);
      return day.add(Duration(minutes: minutes));
    }

    final map = <P, DateTime>{};
    void put(P k, DateTime? v) {
      if (v != null) map[k] = v;
    }

    put(P.fajr, toLocal(tFajr, P.fajr, 0));
    put(P.sunrise, toLocal(tSunrise, P.sunrise, temkinSunrise));
    put(P.dhuhr, toLocal(tDhuhr, P.dhuhr, temkinDhuhr));
    put(P.asr, toLocal(tAsr, P.asr, temkinAsr));
    put(P.maghrib, toLocal(tMaghrib, P.maghrib, temkinMaghrib));
    if (ishaIntervalMin > 0 && map[P.maghrib] != null) {
      map[P.isha] = map[P.maghrib]!
          .add(Duration(minutes: ishaIntervalMin + (offsets[P.isha] ?? 0)));
    } else {
      put(P.isha, toLocal(tIsha, P.isha, 0));
    }

    return DayTimes(date: day, times: map, source: TimeSource.calculated);
  }
}

// =============================================================================
//  5. Qibla
// =============================================================================

class Qibla {
  static const double kaabaLat = 21.4224779;
  static const double kaabaLng = 39.8251832;

  static double bearing(double lat, double lng) {
    final phi1 = lat * math.pi / 180;
    final phi2 = kaabaLat * math.pi / 180;
    final dLng = (kaabaLng - lng) * math.pi / 180;
    final y = math.sin(dLng);
    final x = math.cos(phi1) * math.tan(phi2) - math.sin(phi1) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  static double delta(double from, double to) => ((to - from + 540) % 360) - 180;
}

double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.pow(math.sin(dLng / 2), 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

// =============================================================================
//  6. Tabellen-Parser
// =============================================================================

class TableParser {
  static final _timeRe = RegExp(r'\b([01]?\d|2[0-3])[:.]([0-5]\d)\b');
  static final _fullDateRe = RegExp(r'\b(\d{1,2})[.\-/](\d{1,2})[.\-/](\d{4})\b');

  static Map<String, List<String>> parse(String input, int fallbackYear, int fallbackMonth) {
    final result = <String, List<String>>{};
    for (final rawLine in input.split(RegExp(r'[\r\n]+'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final times = _timeRe.allMatches(line).toList();
      if (times.length < 6) continue;

      int year = fallbackYear, month = fallbackMonth, day = 0;
      final full = _fullDateRe.firstMatch(line);
      if (full != null) {
        day = int.parse(full.group(1)!);
        month = int.parse(full.group(2)!);
        year = int.parse(full.group(3)!);
      } else {
        for (final m in RegExp(r'\b(\d{1,2})\b').allMatches(line)) {
          if (times.any((t) => m.start >= t.start && m.start < t.end)) continue;
          final value = int.parse(m.group(1)!);
          if (value >= 1 && value <= 31) {
            day = value;
            break;
          }
        }
      }
      if (day < 1 || day > 31 || month < 1 || month > 12) continue;

      String two(int v) => v.toString().padLeft(2, '0');
      result['$year-${two(month)}-${two(day)}'] =
          times.take(6).map((m) => '${two(int.parse(m.group(1)!))}:${m.group(2)!}').toList();
    }
    return result;
  }
}

// =============================================================================
//  7. App-Zustand
// =============================================================================

class AppState extends ChangeNotifier {
  AppLang lang = AppLang.de;
  ThemeMode themeMode = ThemeMode.dark;
  AppPalette palette = AppPalette.indigo;
  bool use24h = true;
  TimeSource timeSource = TimeSource.calculated;

  // Berechnung
  String methodId = 'diyanet';
  int ishaIntervalMin = 0;
  int asrShadowFactor = 1; // Diyanet: einfaches Schattenmaß
  double fajrAngle = 14.9;
  double ishaAngle = 13.9;
  bool useTemkin = true;

  double? lat, lng;
  String? placeLabel;
  bool manualLocation = false;
  LocState locState = LocState.unknown;

  Map<P, int> offsets = {for (final p in P.values) p: 0};

  Map<String, List<String>> onlineTimes = {};
  Map<String, List<String>> customTimes = {};
  DateTime? lastSync;
  bool syncing = false;

  List<Mosque> mosques = [];
  int mosqueRadiusKm = 5;
  bool onlySunni = true;
  // Womit wurde die gespeicherte Liste gefunden?
  double? _searchLat, _searchLng;
  int? _searchRadius;
  String? myMosque;
  Mosque? refMosque; // Moschee, auf die sich die Zeiten beziehen
  bool useMosqueLocation = true;
  bool mosquesLoading = false;
  String? mosqueError;

  int tasbihCount = 0, tasbihTarget = 33, dhikrIndex = 0;

  // Kerahat
  bool tutorialDone = false;
  int widgetAlpha = 170; // 0 = unsichtbar, 255 = deckend
  bool showKerahat = false;
  int kerahatSunriseMin = 45;
  int kerahatIstivaMin = 15;
  int kerahatSunsetMin = 45;

  // Tracker
  String userName = '';
  Map<String, List<String>> prayedDays = {}; // Datum -> Namen der Gebete
  Map<String, bool> fastedDays = {}; // Datum -> gefastet
  List<Friend> friends = [];

  late SharedPreferences _p;

  static const _dhikr = ['Subhânallâh', 'Elhamdülillâh', 'Allâhu ekber', 'Lâ ilâhe illallâh', 'Estağfirullâh'];
  String get currentDhikr => _dhikr[dhikrIndex % _dhikr.length];
  List<String> get dhikrList => _dhikr;

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    lang = AppLang.values[_p.getInt('lang') ?? 0];
    themeMode = ThemeMode.values[_p.getInt('theme') ?? ThemeMode.dark.index];
    palette = AppPalette.values[_p.getInt('palette') ?? 0];
    use24h = _p.getBool('use24h') ?? true;
    timeSource = TimeSource.values[_p.getInt('timeSource') ?? 0];
    methodId = _p.getString('methodId') ?? 'diyanet';
    ishaIntervalMin = _p.getInt('ishaInterval') ?? 0;
    asrShadowFactor = _p.getInt('asrFactor') ?? 1;
    fajrAngle = _p.getDouble('fajrAngle') ?? 14.9;
    ishaAngle = _p.getDouble('ishaAngle') ?? 13.9;
    useTemkin = _p.getBool('useTemkin') ?? true;
    lat = _p.getDouble('lat');
    lng = _p.getDouble('lng');
    placeLabel = _p.getString('placeLabel');
    manualLocation = _p.getBool('manualLocation') ?? false;
    if (lat != null && lng != null) locState = LocState.ready;
    tasbihCount = _p.getInt('tasbihCount') ?? 0;
    tasbihTarget = _p.getInt('tasbihTarget') ?? 33;
    dhikrIndex = _p.getInt('dhikrIndex') ?? 0;
    mosqueRadiusKm = _p.getInt('mosqueRadius') ?? 5;
    _searchLat = _p.getDouble('searchLat');
    _searchLng = _p.getDouble('searchLng');
    _searchRadius = _p.getInt('searchRadius');
    onlySunni = _p.getBool('onlySunni') ?? true;
    myMosque = _p.getString('myMosque');
    useMosqueLocation = _p.getBool('useMosqueLocation') ?? true;
    final rm = _p.getString('refMosque');
    if (rm != null) {
      refMosque = Mosque.fromJson(jsonDecode(rm) as Map<String, dynamic>);
    }
    userName = _p.getString('userName') ?? '';
    tutorialDone = _p.getBool('tutorialDone') ?? false;
    widgetAlpha = _p.getInt('widget_alpha') ?? 170;
    showKerahat = _p.getBool('showKerahat') ?? false;
    kerahatSunriseMin = _p.getInt('kSunrise') ?? 45;
    kerahatIstivaMin = _p.getInt('kIstiva') ?? 15;
    kerahatSunsetMin = _p.getInt('kSunset') ?? 45;

    final o = _p.getString('offsets');
    if (o != null) {
      final decoded = jsonDecode(o) as Map<String, dynamic>;
      for (final p in P.values) {
        offsets[p] = (decoded[p.name] as num?)?.toInt() ?? 0;
      }
    }
    onlineTimes = _decodeTable(_p.getString('onlineTimes'));
    customTimes = _decodeTable(_p.getString('customTimes'));
    prayedDays = _decodeTable(_p.getString('prayedDays'));
    final fd = _p.getString('fastedDays');
    if (fd != null) {
      fastedDays = (jsonDecode(fd) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as bool));
    }
    final ls = _p.getInt('lastSync');
    if (ls != null) lastSync = DateTime.fromMillisecondsSinceEpoch(ls);

    final m = _p.getString('mosques');
    if (m != null) {
      mosques = (jsonDecode(m) as List)
          .map((e) => Mosque.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    final f = _p.getString('friends');
    if (f != null) {
      friends = (jsonDecode(f) as List)
          .map((e) => Friend.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  Map<String, List<String>> _decodeTable(String? raw) {
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, List<String>.from(v as List)));
  }

  void _setInt(String key, int value, VoidCallback apply) {
    apply();
    _p.setInt(key, value);
    notifyListeners();
  }

  void setLang(AppLang v) => _setInt('lang', v.index, () => lang = v);
  void setTheme(ThemeMode v) => _setInt('theme', v.index, () => themeMode = v);
  void setPalette(AppPalette v) {
    _setInt('palette', v.index, () => palette = v);
    unawaited(writeWidgetData());
  }
  void setTimeSource(TimeSource v) => _setInt('timeSource', v.index, () => timeSource = v);
  void setAsrFactor(int v) {
    _markCustom();
    _setInt('asrFactor', v, () => asrShadowFactor = v);
  }

  CalcMethod get method =>
      kMethods.firstWhere((m) => m.id == methodId, orElse: () => kMethods.first);

  void applyMethod(String id) {
    final m = kMethods.firstWhere((e) => e.id == id, orElse: () => kMethods.first);
    methodId = m.id;
    fajrAngle = m.fajr;
    ishaAngle = m.isha;
    ishaIntervalMin = m.ishaInterval;
    asrShadowFactor = m.asr;
    useTemkin = m.temkin;
    offsets[P.sunrise] = m.offsetSunrise;
    offsets[P.maghrib] = m.offsetMaghrib;
    _p.setString('offsets', jsonEncode({for (final e in offsets.entries) e.key.name: e.value}));
    _p.setString('methodId', m.id);
    _p.setDouble('fajrAngle', fajrAngle);
    _p.setDouble('ishaAngle', ishaAngle);
    _p.setInt('ishaInterval', ishaIntervalMin);
    _p.setInt('asrFactor', asrShadowFactor);
    _p.setBool('useTemkin', useTemkin);
    notifyListeners();
    if (timeSource == TimeSource.online) unawaited(syncOnline());
  }

  /// Wird gesetzt, sobald von Hand an den Werten gedreht wird.
  void _markCustom() {
    if (methodId != 'custom') {
      methodId = 'custom';
      _p.setString('methodId', 'custom');
    }
  }

  void setAngles({double? fajr, double? isha}) {
    _markCustom();
    if (fajr != null) {
      fajrAngle = fajr.clamp(8.0, 22.0);
      _p.setDouble('fajrAngle', fajrAngle);
    }
    if (isha != null) {
      ishaAngle = isha.clamp(8.0, 22.0);
      _p.setDouble('ishaAngle', ishaAngle);
    }
    notifyListeners();
  }

  void setUseTemkin(bool v) {
    _markCustom();
    useTemkin = v;
    _p.setBool('useTemkin', v);
    notifyListeners();
  }

  void setUse24h(bool v) {
    use24h = v;
    _p.setBool('use24h', v);
    notifyListeners();
  }

  void setOffset(P p, int minutes) {
    offsets[p] = minutes.clamp(-30, 30);
    _p.setString('offsets', jsonEncode({for (final e in offsets.entries) e.key.name: e.value}));
    notifyListeners();
  }

  void setWidgetAlpha(int v) {
    widgetAlpha = v.clamp(40, 255);
    _p.setInt('widget_alpha', widgetAlpha);
    notifyListeners();
  }

  DateTime _lastWidgetWrite = DateTime(2000);

  @override
  void notifyListeners() {
    super.notifyListeners();
    // Die Startbildschirm-Widgets lesen diese Werte direkt aus dem Speicher.
    if (DateTime.now().difference(_lastWidgetWrite).inSeconds > 2) {
      _lastWidgetWrite = DateTime.now();
      unawaited(writeWidgetData());
    }
  }

  Future<void> writeWidgetData() async {
    try {
      final now = DateTime.now();
      final day = timesFor(now);
      final next = nextPrayer(now);
      final entries = <List<String>>[];
      if (day != null) {
        for (final p in kPrayers) {
          entries.add([p.label, fmtTime(day[p])]);
        }
      }
      final payload = {
        'date': longDate(now),
        'label': refMosque?.name ?? locationLabel,
        'next': next?.key.label ?? '',
        'times': entries,
      };
      await _p.setString('widget_times', jsonEncode(payload));
      await _p.setInt('widget_alpha', widgetAlpha);
      int rgb(Color c) =>
          ((c.r * 255).round() << 16) | ((c.g * 255).round() << 8) | (c.b * 255).round();
      await _p.setInt('widget_bg', rgb(pal.deep));
      await _p.setInt('widget_gold', rgb(pal.gold));
      if (lat != null && lng != null) {
        await _p.setString('widget_qibla', Qibla.bearing(lat!, lng!).toStringAsFixed(1));
      }
      try {
        await const MethodChannel('com.nurislam.nur_islam/route').invokeMethod('refreshWidgets');
      } catch (_) {}
    } catch (_) {
      // Widgets sind Beiwerk — ein Fehler hier darf die App nicht stören.
    }
  }

  void finishTutorial() {
    tutorialDone = true;
    _p.setBool('tutorialDone', true);
    notifyListeners();
  }

  void setShowKerahat(bool v) {
    showKerahat = v;
    _p.setBool('showKerahat', v);
    notifyListeners();
  }

  void setKerahatMinutes({int? sunrise, int? istiva, int? sunset}) {
    if (sunrise != null) {
      kerahatSunriseMin = sunrise.clamp(0, 90);
      _p.setInt('kSunrise', kerahatSunriseMin);
    }
    if (istiva != null) {
      kerahatIstivaMin = istiva.clamp(0, 60);
      _p.setInt('kIstiva', kerahatIstivaMin);
    }
    if (sunset != null) {
      kerahatSunsetMin = sunset.clamp(0, 90);
      _p.setInt('kSunset', kerahatSunsetMin);
    }
    notifyListeners();
  }

  /// Die drei Kerahat-Fenster eines Tages: Beginn, Ende, Bezeichner.
  List<(DateTime, DateTime, String)> kerahatWindows(DateTime date) {
    final d = timesFor(date);
    if (d == null) return const [];
    final out = <(DateTime, DateTime, String)>[];
    final sr = d[P.sunrise], dh = d[P.dhuhr], mg = d[P.maghrib];
    if (sr != null && kerahatSunriseMin > 0) {
      out.add((sr, sr.add(Duration(minutes: kerahatSunriseMin)), 'k_israk'));
    }
    if (dh != null && kerahatIstivaMin > 0) {
      out.add((dh.subtract(Duration(minutes: kerahatIstivaMin)), dh, 'k_istiva'));
    }
    if (mg != null && kerahatSunsetMin > 0) {
      out.add((mg.subtract(Duration(minutes: kerahatSunsetMin)), mg, 'k_isfirar'));
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    return out;
  }

  (DateTime, DateTime, String)? currentKerahat(DateTime now) {
    for (final w in kerahatWindows(now)) {
      if (!now.isBefore(w.$1) && now.isBefore(w.$2)) return w;
    }
    return null;
  }

  (DateTime, DateTime, String)? nextKerahat(DateTime now) {
    for (final w in kerahatWindows(now)) {
      if (w.$1.isAfter(now)) return w;
    }
    final tomorrow = kerahatWindows(now.add(const Duration(days: 1)));
    return tomorrow.isEmpty ? null : tomorrow.first;
  }

  void setUserName(String v) {
    userName = v.trim();
    _p.setString('userName', userName);
    notifyListeners();
  }

  // --- Tesbih ---
  /// Ziel 0 bedeutet: ohne Begrenzung weiterzählen.
  bool get tasbihAtTarget => tasbihTarget > 0 && tasbihCount >= tasbihTarget;

  /// Zählt hoch und bleibt beim eingestellten Ziel stehen — Zurücksetzen von Hand.
  void tasbihIncrement() {
    if (tasbihAtTarget) {
      HapticFeedback.heavyImpact();
      return;
    }
    tasbihCount++;
    _p.setInt('tasbihCount', tasbihCount);
    if (tasbihAtTarget) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.selectionClick();
    }
    notifyListeners();
  }

  void tasbihReset() {
    tasbihCount = 0;
    _p.setInt('tasbihCount', 0);
    notifyListeners();
  }

  void setTasbihTarget(int v) {
    tasbihTarget = v;
    _p.setInt('tasbihTarget', v);
    if (v > 0 && tasbihCount > v) {
      tasbihCount = v;
      _p.setInt('tasbihCount', v);
    }
    notifyListeners();
  }

  void setDhikrIndex(int v) {
    dhikrIndex = v;
    _p.setInt('dhikrIndex', v);
    notifyListeners();
  }

  // --- Tracker ---
  String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool hasPrayed(DateTime day, P p) => (prayedDays[dayKey(day)] ?? []).contains(p.name);

  void togglePrayed(DateTime day, P p) {
    final key = dayKey(day);
    final list = List<String>.from(prayedDays[key] ?? []);
    if (list.contains(p.name)) {
      list.remove(p.name);
    } else {
      list.add(p.name);
      HapticFeedback.selectionClick();
    }
    if (list.isEmpty) {
      prayedDays.remove(key);
    } else {
      prayedDays[key] = list;
    }
    _p.setString('prayedDays', jsonEncode(prayedDays));
    notifyListeners();
  }

  int prayedCount(DateTime day) => (prayedDays[dayKey(day)] ?? []).length;

  /// Zusammenhängende Tage mit fünf Gebeten, rückwärts ab gestern bzw. heute.
  int get streak {
    var count = 0;
    var day = DateTime.now();
    if (prayedCount(day) < 5) day = day.subtract(const Duration(days: 1));
    while (prayedCount(day) >= 5) {
      count++;
      day = day.subtract(const Duration(days: 1));
    }
    return count;
  }

  // --- Fasten-Tracker ---
  bool hasFasted(DateTime day) => fastedDays[dayKey(day)] ?? false;

  void toggleFasted(DateTime day) {
    final key = dayKey(day);
    final cur = fastedDays[key] ?? false;
    fastedDays[key] = !cur;
    if (!cur) HapticFeedback.selectionClick();
    _p.setString('fastedDays', jsonEncode(fastedDays));
    notifyListeners();
  }

  int get fastingStreak {
    var count = 0;
    var day = DateTime.now();
    if (!hasFasted(day)) day = day.subtract(const Duration(days: 1));
    while (hasFasted(day)) {
      count++;
      day = day.subtract(const Duration(days: 1));
    }
    return count;
  }

  int get fastedThisMonth {
    final now = DateTime.now();
    var n = 0;
    for (var i = 1; i <= now.day; i++) {
      if (hasFasted(DateTime(now.year, now.month, i))) n++;
    }
    return n;
  }

  List<int> get lastSevenDays {
    final today = DateTime.now();
    return List.generate(7, (i) => prayedCount(today.subtract(Duration(days: 6 - i))));
  }

  List<int> get lastThirtyDays {
    final today = DateTime.now();
    return List.generate(30, (i) => prayedCount(today.subtract(Duration(days: 29 - i))));
  }

  int get weekTotal => lastSevenDays.fold(0, (a, b) => a + b);
  int get monthTotal => lastThirtyDays.fold(0, (a, b) => a + b);
  double get weekAverage => weekTotal / 7;
  double get monthAverage => monthTotal / 30;

  static const String _alphabet =
      '0123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

  /// 30 Tageswerte (je 0–5) werden zu einer Zahl gepackt und kurz kodiert.
  /// Ergebnis: rund 15 Zeichen plus Name statt mehrerer hundert.
  String buildShareCode() {
    final today = DateTime.now();
    var value = BigInt.zero;
    final six = BigInt.from(6);
    for (var i = 0; i < 30; i++) {
      final d = today.subtract(Duration(days: 29 - i));
      value = value * six + BigInt.from(prayedCount(d).clamp(0, 5));
    }
    final base = BigInt.from(_alphabet.length);
    final buffer = StringBuffer();
    var v = value;
    if (v == BigInt.zero) buffer.write(_alphabet[0]);
    while (v > BigInt.zero) {
      buffer.write(_alphabet[(v % base).toInt()]);
      v = v ~/ base;
    }
    // Anker ist der heutige Tag, damit der Empfänger die Werte zuordnen kann.
    final anchor = today.difference(DateTime(2020)).inDays;
    final name = userName.isEmpty ? 'Freund' : userName.replaceAll('~', '');
    return 'NI~$anchor~${buffer.toString()}~$name';
  }

  /// Liest einen Code ein. Der Name des Absenders wird übernommen.
  bool addFriendFromCode(String raw) {
    try {
      final token = raw
          .trim()
          .split(RegExp(r'\s+'))
          .firstWhere((t) => t.startsWith('NI~'), orElse: () => '');
      if (token.isEmpty) return false;
      final parts = token.split('~');
      if (parts.length < 4) return false;

      final anchor = int.parse(parts[1]);
      final encoded = parts[2];
      final name = parts.sublist(3).join('~').trim();
      if (name.isEmpty) return false;

      final base = BigInt.from(_alphabet.length);
      var value = BigInt.zero;
      for (var i = encoded.length - 1; i >= 0; i--) {
        final idx = _alphabet.indexOf(encoded[i]);
        if (idx < 0) return false;
        value = value * base + BigInt.from(idx);
      }

      final six = BigInt.from(6);
      final counts = List<int>.filled(30, 0);
      for (var i = 29; i >= 0; i--) {
        counts[i] = (value % six).toInt();
        value = value ~/ six;
      }

      final anchorDate = DateTime(2020).add(Duration(days: anchor));
      final days = <String, int>{};
      for (var i = 0; i < 30; i++) {
        final d = anchorDate.subtract(Duration(days: 29 - i));
        if (counts[i] > 0) days[dayKey(d)] = counts[i];
      }

      friends.removeWhere((f) => f.name.toLowerCase() == name.toLowerCase());
      friends.add(Friend(name: name, days: days, updated: DateTime.now()));
      _saveFriends();
      return true;
    } catch (_) {
      return false;
    }
  }

  void removeFriend(String name) {
    friends.removeWhere((f) => f.name == name);
    _saveFriends();
  }

  void _saveFriends() {
    _p.setString('friends', jsonEncode(friends.map((f) => f.toJson()).toList()));
    notifyListeners();
  }

  String buildInviteText() {
    final name = userName.isEmpty ? '' : '$userName ';
    final code = buildShareCode();
    return switch (lang) {
      AppLang.de =>
        '${name}lädt dich zu Nur Islam ein — Gebetszeiten, Qibla und Tesbih, kostenlos '
            'und ohne Konto.\n\nMein Code zum Einfügen in der App:\n$code',
      AppLang.tr =>
        '$name seni Nur Islam\'a davet ediyor — namaz vakitleri, kıble ve tesbih, '
            'ücretsiz ve hesapsız.\n\nUygulamaya yapıştırılacak kodum:\n$code',
      AppLang.en =>
        '${name}invites you to Nur Islam — prayer times, qibla and tasbih, free and '
            'without an account.\n\nMy code to paste into the app:\n$code',
    };
  }

  // --- Standort ---
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
      await _storeLocation(pos.latitude, pos.longitude, null, manual: false);
      if (timeSource == TimeSource.online) unawaited(syncOnline());
    } catch (_) {
      locState = (lat != null && lng != null) ? LocState.ready : LocState.error;
      notifyListeners();
    }
  }

  Future<void> setManualLocation(double newLat, double newLng, String? label) async {
    await _storeLocation(newLat, newLng, label, manual: true);
    if (timeSource == TimeSource.online) unawaited(syncOnline());
  }

  Future<void> _storeLocation(double newLat, double newLng, String? label,
      {required bool manual}) async {
    lat = newLat;
    lng = newLng;
    placeLabel = label;
    manualLocation = manual;
    locState = LocState.ready;
    await _p.setDouble('lat', newLat);
    await _p.setDouble('lng', newLng);
    await _p.setBool('manualLocation', manual);
    if (label == null) {
      await _p.remove('placeLabel');
    } else {
      await _p.setString('placeLabel', label);
    }
    notifyListeners();
  }

  Future<List<(String, double, double)>> searchPlace(String query) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'json',
      'limit': '8',
      'accept-language': lang.name,
    });
    final res = await http.get(uri, headers: {
      'User-Agent': 'NurIslamApp/3.0 (persönliche Nutzung)',
    }).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return [];
    return (jsonDecode(res.body) as List)
        .map((e) => (
              e['display_name'] as String,
              double.parse(e['lat'] as String),
              double.parse(e['lon'] as String),
            ))
        .toList();
  }

  // --- Moscheen ---
  /// Ausrichtungen, die bei aktivem Filter nicht angezeigt werden.
  static const Set<String> _nonSunni = {
    'alevi', 'alevism', 'alevite', 'bektashi', 'shia', 'shi\'a', 'shiite',
    'ismaili', 'twelver', 'zaidi', 'ibadi', 'ahmadiyya', 'ahmadi',
    'alawite', 'nusayri', 'druze', 'quranist',
  };
  static const List<String> _nonSunniNames = ['cemevi', 'cem evi', 'cemvakfı', 'cem vakfı', 'alevi'];

  bool _passesFilter(String name, String? denomination) {
    if (!onlySunni) return true;
    // Nur ausschliessen, was eindeutig einer anderen Ausrichtung zugeordnet ist.
    // Unbekannte oder fehlende Angaben bleiben drin — sonst verschwinden zu viele.
    final d = denomination?.toLowerCase().trim();
    if (d != null && d.isNotEmpty) {
      for (final part in d.split(RegExp(r'[;,/ ]+'))) {
        if (_nonSunni.contains(part.trim())) return false;
      }
    }
    final n = name.toLowerCase();
    return !_nonSunniNames.any(n.contains);
  }

    /// Fragt mehrere Overpass-Spiegelserver parallel an und verwendet die
  /// schnellste erfolgreiche Antwort, damit die Moscheensuche nicht durch
  /// einen einzelnen langsamen/ueberlasteten Server ausgebremst wird.
  Future<http.Response> _queryOverpassFastest(String query) {
    const endpoints = [
      'https://overpass-api.de/api/interpreter',
      'https://overpass.kumi.systems/api/interpreter',
      'https://overpass.openstreetmap.ru/api/interpreter',
    ];
    final completer = Completer<http.Response>();
    var pending = endpoints.length;
    Object? lastError;
    for (final ep in endpoints) {
      http
          .post(Uri.parse(ep),
              headers: {'User-Agent': 'NurIslamApp/3.0'}, body: {'data': query})
          .timeout(const Duration(seconds: 20))
          .then((res) {
        pending--;
        if (completer.isCompleted) return;
        if (res.statusCode == 200) {
          completer.complete(res);
        } else {
          lastError = Exception('HTTP ${res.statusCode}');
          if (pending == 0) completer.completeError(lastError!);
        }
      }).catchError((e) {
        pending--;
        lastError = e;
        if (pending == 0 && !completer.isCompleted) completer.completeError(e);
      });
    }
    return completer.future;
  }

Future<void> loadMosques() async {
    if (lat == null || lng == null || mosquesLoading) return;
    mosquesLoading = true;
    mosqueError = null;
    notifyListeners();
    try {
      final r = mosqueRadiusKm * 1000;
      final query = '''
[out:json][timeout:30];
(
  node["amenity"="place_of_worship"]["religion"="muslim"](around:$r,$lat,$lng);
  way["amenity"="place_of_worship"]["religion"="muslim"](around:$r,$lat,$lng);
);
out center 100;
''';
      final res = await _queryOverpassFastest(query);
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');

      final elements = (jsonDecode(res.body) as Map<String, dynamic>)['elements'] as List;
      final found = <Mosque>[];
      for (final e in elements) {
        final el = e as Map<String, dynamic>;
        final tags = (el['tags'] as Map<String, dynamic>?) ?? {};
        final mLat = (el['lat'] ?? el['center']?['lat']) as num?;
        final mLng = (el['lon'] ?? el['center']?['lon']) as num?;
        if (mLat == null || mLng == null) continue;
        final name = (tags['name'] as String?) ?? 'Moschee';
        final denom = tags['denomination'] as String?;
        if (!_passesFilter(name, denom)) continue;
        final street = [tags['addr:street'], tags['addr:housenumber']]
            .whereType<String>()
            .join(' ');
        String? tag(List<String> keys) {
          for (final k in keys) {
            final v = tags[k];
            if (v is String && v.trim().isNotEmpty) return v.trim();
          }
          return null;
        }

        found.add(Mosque(
          name: name,
          lat: mLat.toDouble(),
          lng: mLng.toDouble(),
          street: street.isEmpty ? null : street,
          city: tags['addr:city'] as String?,
          denomination: denom,
          phone: tag(['phone', 'contact:phone', 'contact:mobile']),
          website: tag(['website', 'contact:website', 'contact:facebook']),
          openingHours: tag(['opening_hours', 'service_times']),
        ));
      }
      // Overpass liefert gelegentlich Treffer knapp ausserhalb des Umkreises und
      // dieselbe Moschee doppelt (einmal als Punkt, einmal als Flaeche).
      final limit = mosqueRadiusKm.toDouble();
      final within = found
          .where((m) => distanceKm(lat!, lng!, m.lat, m.lng) <= limit)
          .toList()
        ..sort((a, b) => distanceKm(lat!, lng!, a.lat, a.lng)
            .compareTo(distanceKm(lat!, lng!, b.lat, b.lng)));

      final unique = <Mosque>[];
      for (final m in within) {
        final dup = unique.any((u) =>
            u.name.toLowerCase() == m.name.toLowerCase() &&
            distanceKm(u.lat, u.lng, m.lat, m.lng) < 0.15);
        if (!dup) unique.add(m);
      }

      mosques = unique;
      _searchLat = lat;
      _searchLng = lng;
      _searchRadius = mosqueRadiusKm;
      await _p.setString('mosques', jsonEncode(unique.map((m) => m.toJson()).toList()));
      await _p.setDouble('searchLat', lat!);
      await _p.setDouble('searchLng', lng!);
      await _p.setInt('searchRadius', mosqueRadiusKm);
    } catch (e) {
      mosqueError = e.toString();
    }
    mosquesLoading = false;
    notifyListeners();
  }

  /// Zeigt nur, was wirklich im gewaehlten Umkreis liegt — auch wenn die
  /// gespeicherte Liste aus einer frueheren, groesseren Suche stammt.
  List<Mosque> get visibleMosques {
    if (lat == null || lng == null) return const [];
    return mosques
        .where((m) => distanceKm(lat!, lng!, m.lat, m.lng) <= mosqueRadiusKm.toDouble())
        .toList()
      ..sort((a, b) => distanceKm(lat!, lng!, a.lat, a.lng)
          .compareTo(distanceKm(lat!, lng!, b.lat, b.lng)));
  }

  /// Wahr, wenn die gespeicherte Liste zu einem anderen Ort oder Umkreis gehoert.
  bool get mosquesStale {
    if (lat == null || lng == null) return false;
    if (_searchRadius == null || _searchLat == null || _searchLng == null) return true;
    if (_searchRadius != mosqueRadiusKm) return true;
    return distanceKm(_searchLat!, _searchLng!, lat!, lng!) > 0.5;
  }

  void setMosqueRadius(int km) {
    mosqueRadiusKm = km;
    _p.setInt('mosqueRadius', km);
    notifyListeners();
    loadMosques();
  }

  void setOnlySunni(bool v) {
    onlySunni = v;
    _p.setBool('onlySunni', v);
    notifyListeners();
    loadMosques();
  }

  void setMyMosque(String? name) {
    myMosque = name;
    if (name == null) {
      _p.remove('myMosque');
    } else {
      _p.setString('myMosque', name);
    }
    notifyListeners();
  }

  /// Legt fest, auf welche Moschee sich die angezeigten Zeiten beziehen.
  void setReferenceMosque(Mosque? m) {
    refMosque = m;
    myMosque = m?.name;
    if (m == null) {
      _p.remove('refMosque');
      _p.remove('myMosque');
    } else {
      _p.setString('refMosque', jsonEncode(m.toJson()));
      _p.setString('myMosque', m.name);
    }
    notifyListeners();
    if (timeSource == TimeSource.online) unawaited(syncOnline());
  }

  void setUseMosqueLocation(bool v) {
    useMosqueLocation = v;
    _p.setBool('useMosqueLocation', v);
    notifyListeners();
    if (timeSource == TimeSource.online) unawaited(syncOnline());
  }

  /// Koordinaten, mit denen gerechnet wird — Moschee, falls gewaehlt.
  double? get calcLat =>
      (useMosqueLocation && refMosque != null) ? refMosque!.lat : lat;
  double? get calcLng =>
      (useMosqueLocation && refMosque != null) ? refMosque!.lng : lng;

  String get timeSourceLabel =>
      refMosque?.name ?? (placeLabel?.split(',').first.trim() ?? tr('src_calc_short'));

  // --- Online-Abgleich ---
  Future<bool> syncOnline() async {
    if (lat == null || lng == null || syncing) return false;
    syncing = true;
    notifyListeners();
    var ok = false;
    try {
      final now = DateTime.now();
      for (var i = 0; i < 2; i++) {
        final d = DateTime(now.year, now.month + i, 1);
        final uri = Uri.https('api.aladhan.com', '/v1/calendar', {
          'latitude': '${calcLat ?? lat}',
          'longitude': '${calcLng ?? lng}',
          'method': '13', // Diyanet İşleri Başkanlığı
          'school': asrShadowFactor == 2 ? '1' : '0',
          'month': '${d.month}',
          'year': '${d.year}',
        });
        final res = await http.get(uri).timeout(const Duration(seconds: 25));
        if (res.statusCode != 200) continue;
        final data = (jsonDecode(res.body) as Map<String, dynamic>)['data'] as List;
        for (final entry in data) {
          final e = entry as Map<String, dynamic>;
          final parts = (e['date']['gregorian']['date'] as String).split('-');
          final key = '${parts[2]}-${parts[1]}-${parts[0]}';
          final t = e['timings'] as Map<String, dynamic>;
          String clean(String s) => s.split(' ').first.trim();
          onlineTimes[key] = [
            clean(t['Fajr'] as String), clean(t['Sunrise'] as String),
            clean(t['Dhuhr'] as String), clean(t['Asr'] as String),
            clean(t['Maghrib'] as String), clean(t['Isha'] as String),
          ];
        }
        ok = true;
      }
      if (ok) {
        final cutoff = DateTime.now().subtract(const Duration(days: 70));
        onlineTimes.removeWhere((k, _) {
          final d = DateTime.tryParse(k);
          return d != null && d.isBefore(cutoff);
        });
        lastSync = DateTime.now();
        await _p.setString('onlineTimes', jsonEncode(onlineTimes));
        await _p.setInt('lastSync', lastSync!.millisecondsSinceEpoch);
      }
    } catch (_) {
      ok = false;
    }
    syncing = false;
    notifyListeners();
    return ok;
  }

  Future<void> saveCustomTable(Map<String, List<String>> table) async {
    customTimes.addAll(table);
    await _p.setString('customTimes', jsonEncode(customTimes));
    notifyListeners();
  }

  Future<void> clearCustomTable() async {
    customTimes.clear();
    await _p.remove('customTimes');
    notifyListeners();
  }

  // --- Zeiten ---
  DayTimes? _fromTable(Map<String, List<String>> table, DateTime day, TimeSource src) {
    final row = table[dayKey(day)];
    if (row == null || row.length < 6) return null;
    final map = <P, DateTime>{};
    for (var i = 0; i < 6; i++) {
      final hm = row[i].split(':');
      if (hm.length < 2) return null;
      final h = int.tryParse(hm[0]), m = int.tryParse(hm[1]);
      if (h == null || m == null) return null;
      final key = P.values[i];
      map[key] = day.add(Duration(hours: h, minutes: m + (offsets[key] ?? 0)));
    }
    return DayTimes(date: day, times: map, source: src);
  }

  DayTimes? timesFor(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final custom = _fromTable(customTimes, day, TimeSource.custom);
    if (custom != null) return custom;
    final cLat = calcLat, cLng = calcLng;
    if (cLat == null || cLng == null) return null;
    if (timeSource == TimeSource.online) {
      final online = _fromTable(onlineTimes, day, TimeSource.online);
      if (online != null) return online;
    }
    return PrayerCalculator.compute(
      date: day,
      lat: cLat,
      lng: cLng,
      shadowFactor: asrShadowFactor,
      fajrAngle: fajrAngle,
      ishaAngle: ishaAngle,
      useTemkin: useTemkin,
      ishaIntervalMin: ishaIntervalMin,
      offsets: offsets,
    );
  }

  MapEntry<P, DateTime>? nextPrayer(DateTime now) {
    final today = timesFor(now);
    if (today == null) return null;
    for (final p in kPrayers) {
      final t = today[p];
      if (t != null && t.isAfter(now)) return MapEntry(p, t);
    }
    final f = timesFor(now.add(const Duration(days: 1)))?[P.fajr];
    return f == null ? null : MapEntry(P.fajr, f);
  }

  MapEntry<P, DateTime>? currentPeriod(DateTime now) {
    final today = timesFor(now);
    if (today == null) return null;
    MapEntry<P, DateTime>? last;
    for (final p in P.values) {
      final t = today[p];
      if (t != null && !t.isAfter(now)) last = MapEntry(p, t);
    }
    if (last != null) return last;
    final i = timesFor(now.subtract(const Duration(days: 1)))?[P.isha];
    return i == null ? null : MapEntry(P.isha, i);
  }

  String get locationLabel {
    if (lat == null) return '—';
    if (placeLabel != null && placeLabel!.isNotEmpty) {
      return placeLabel!.split(',').take(2).join(',').trim();
    }
    return '${lat!.toStringAsFixed(3)}°, ${lng!.toStringAsFixed(3)}°';
  }
}

String fmtTime(DateTime? t) {
  if (t == null) return '—';
  if (appState.use24h) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

String fmtDuration(Duration d) {
  if (d.isNegative) d = Duration.zero;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

Future<void> openMaps(double lat, double lng, [String? label]) async {
  final q = label == null ? '$lat,$lng' : Uri.encodeComponent(label);
  await launchUrl(
    Uri.parse('https://www.google.com/maps/search/?api=1&query=$q&center=$lat,$lng'),
    mode: LaunchMode.externalApplication,
  );
}

void copyToClipboard(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('copied'))));
}

// =============================================================================
//  8. App-Gerüst
// =============================================================================

class NurIslamApp extends StatelessWidget {
  const NurIslamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) => MaterialApp(
        title: 'Nur Islam',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light, appState.palette),
        darkTheme: buildTheme(Brightness.dark, appState.palette),
        themeMode: appState.themeMode,
        home: const RootShell(),
      ),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});
  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;  static const MethodChannel _routeChannel = MethodChannel('com.nurislam.nur_islam/route');

  @override
  void initState() {
    super.initState(); _routeChannel.setMethodCallHandler((call) async { if (call.method == 'openRoute') { if (call.arguments == 'qibla') { if (mounted) setState(() => _index = 2); } else if (call.arguments == 'times') { if (mounted) setState(() => _index = 0); } } }); _routeChannel.invokeMethod<String>('getInitialRoute').then((route) { if (route == 'qibla' && mounted) { setState(() => _index = 2); } else if (route == 'times' && mounted) { setState(() => _index = 0); } }).catchError((_) {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (appState.locState != LocState.ready && !appState.manualLocation) {
        appState.refreshLocation();
      }
      if (!appState.tutorialDone && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const OnboardingDialog(),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        final pages = <Widget>[
          TimesTab(),
          MosquesTab(),
          QiblaTab(),
          TasbihTab(),
          CommunityPage(),
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
                icon: const Icon(Icons.mosque_outlined),
                selectedIcon: const Icon(Icons.mosque),
                label: tr('tab_mosques'),
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
                icon: const Icon(Icons.groups_outlined),
                selectedIcon: const Icon(Icons.groups),
                label: tr('tab_community'),
              ),
            ],
          ),
        );
      },
    );
  }
}

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
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700, letterSpacing: -0.5)),
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

class LocationNotice extends StatelessWidget {
  const LocationNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final s = appState.locState;
    if (s == LocState.loading) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(tr('location_loading')),
        ]),
      );
    }

    final message = switch (s) {
      LocState.serviceOff => tr('location_service_off'),
      LocState.denied => tr('location_denied'),
      LocState.deniedForever => tr('location_denied_forever'),
      _ => tr('location_needed'),
    };

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.location_off_outlined, size: 44, color: Theme.of(context).colorScheme.outline),
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
          label: Text(s == LocState.deniedForever || s == LocState.serviceOff
              ? tr('open_settings')
              : tr('allow_location')),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const LocationPickerPage())),
          icon: const Icon(Icons.travel_explore, size: 18),
          label: Text(tr('choose_manually')),
        ),
      ]),
    );
  }
}

// =============================================================================
//  9. Reiter 1 — Zeiten mit Tracker
// =============================================================================

class TimesTab extends StatefulWidget {
  const TimesTab({super.key});
  @override
  State<TimesTab> createState() => _TimesTabState();
}

class _TimesTabState extends State<TimesTab> {
  Timer? _ticker;
  DateTime _now = DateTime.now();
  DateTime _selected = DateTime.now();
  int _direction = 1; // 1 = vorwärts, -1 = zurück (steuert die Wischrichtung)

  bool get _isToday =>
      _selected.year == _now.year && _selected.month == _now.month && _selected.day == _now.day;

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

  void _shiftDay(int days) {
    setState(() {
      _direction = days >= 0 ? 1 : -1;
      _selected = _selected.add(Duration(days: days));
    });
    HapticFeedback.selectionClick();
  }

  void _jumpTo(DateTime target) {
    setState(() {
      _direction = target.isBefore(_selected) ? -1 : 1;
      _selected = target;
    });
  }

  Future<void> _pickDay() async {
    final picked = await Navigator.push<DateTime>(
      context,
      MaterialPageRoute(builder: (_) => CalendarPage(initial: _selected)),
    );
    if (picked != null) _jumpTo(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final day = appState.timesFor(_selected);

    return RefreshIndicator(
      onRefresh: () async {
        if (!appState.manualLocation) await appState.refreshLocation();
        if (appState.timeSource == TimeSource.online) await appState.syncOnline();
      },
      child: GestureDetector(
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -250) _shiftDay(1);
          if (v > 250) _shiftDay(-1);
        },
        child: Column(children: [
          _DayHeader(
              date: _selected,
              isToday: _isToday,
              onPrev: () => _shiftDay(-1),
              onNext: () => _shiftDay(1),
              onPick: _pickDay,
            onToday: () => _jumpTo(DateTime.now()),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (current, previous) =>
                  Stack(alignment: Alignment.topCenter, children: [
                ...previous,
                if (current != null) current,
              ]),
              transitionBuilder: (child, animation) {
                final incoming = child.key == ValueKey(appState.dayKey(_selected));
                final begin = Offset(
                  incoming ? _direction * 0.25 : -_direction * 0.25,
                  0,
                );
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: begin, end: Offset.zero)
                        .animate(animation),
                    child: child,
                  ),
                );
              },
              child: ListView(
                key: ValueKey(appState.dayKey(_selected)),
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  if (day == null)
              const LocationNotice()
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _isToday
                    ? _NextPrayerCard(now: _now)
                    : _DaySummaryCard(day: day, date: _selected),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Card(
                  child: Column(
                    children: [
                      for (final p in P.values)
                        _PrayerRow(p: p, day: day, date: _selected, now: _now, isToday: _isToday),
                    ],
                  ),
                ),
              ),
              if (appState.showKerahat) ...[
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _KerahatCard(date: _selected, now: _now, isToday: _isToday),
                ),
              ],
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _TrackerCard(now: _selected),
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
                        Row(children: [
                          Icon(Icons.auto_awesome_outlined, size: 18, color: pal.gold),
                          const SizedBox(width: 8),
                          Text(tr('motivation'),
                              style: theme.textTheme.labelLarge
                                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        ]),
                        const SizedBox(height: 10),
                        Text(motivationOfTheDay(_selected),
                            style: theme.textTheme.titleMedium?.copyWith(height: 1.4)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(children: [
                  Icon(
                    switch (day.source) {
                      TimeSource.custom => Icons.edit_note,
                      TimeSource.online => Icons.cloud_done_outlined,
                      TimeSource.calculated => Icons.offline_bolt_outlined,
                    },
                    size: 15,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      switch (day.source) {
                        TimeSource.custom => tr('source_custom'),
                        TimeSource.online => tr('source_synced'),
                        TimeSource.calculated => tr('source_local'),
                      },
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ),
                ]),
              ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(tr('swipe_hint'),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                  ),
                ],
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Kopfzeile mit Tagesnavigation und der Moschee, auf die sich die Zeiten beziehen.
class _DayHeader extends StatelessWidget {
  final DateTime date;
  final bool isToday;
  final VoidCallback onPrev, onNext, onPick, onToday;
  const _DayHeader({
    required this.date,
    required this.isToday,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
    required this.onToday,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 8),
              Expanded(
                child: Text(appState.locationLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
              // Quelle der Zeiten, antippbar
              Flexible(
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const MosqueSourcePage())),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: pal.gold.withValues(alpha: 0.45)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(appState.refMosque != null ? Icons.mosque : Icons.calculate_outlined,
                          size: 13, color: pal.gold),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          appState.timeSourceLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(color: pal.gold),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              IconButton(
                onPressed: onPrev,
                icon: const Icon(Icons.chevron_left),
                tooltip: '-1',
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onPick,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(children: [
                      Text(longDate(date),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                      if (!isToday)
                        Text(tr('pick_day'),
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: theme.colorScheme.outline)),
                    ]),
                  ),
                ),
              ),
              IconButton(
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right),
                tooltip: '+1',
              ),
              if (!isToday)
                TextButton(onPressed: onToday, child: Text(tr('today_button')))
              else
                IconButton(onPressed: onPick, icon: const Icon(Icons.calendar_month_outlined)),
              IconButton(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const MoreTab())),
                icon: const Icon(Icons.settings_outlined),
                tooltip: tr('tab_settings'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Übersicht für einen Tag, der nicht heute ist.
class _DaySummaryCard extends StatelessWidget {
  final DayTimes day;
  final DateTime date;
  const _DaySummaryCard({required this.day, required this.date});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [pal.primary, pal.deep],
        ),
        border: Border.all(color: pal.gold.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final p in [P.fajr, P.dhuhr, P.asr, P.maghrib, P.isha])
            Column(children: [
              Icon(p.icon, size: 16, color: pal.gold),
              const SizedBox(height: 6),
              Text(fmtTime(day[p]),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ]),
        ],
      ),
    );
  }
}

/// Kerahat-Karte mit Countdown.
class _KerahatCard extends StatelessWidget {
  final DateTime date, now;
  final bool isToday;
  const _KerahatCard({required this.date, required this.now, required this.isToday});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final windows = appState.kerahatWindows(date);
    if (windows.isEmpty) return const SizedBox.shrink();

    final current = isToday ? appState.currentKerahat(now) : null;
    final next = isToday ? appState.nextKerahat(now) : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.do_not_disturb_on_outlined, size: 18, color: pal.gold),
            const SizedBox(width: 8),
            Text(tr('kerahat'),
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
          if (isToday) ...[
            const SizedBox(height: 10),
            if (current != null)
              Row(children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${tr('kerahat_now')} · ${tr('kerahat_ends')} '
                      '${fmtDuration(current.$2.difference(now))}'),
                ),
              ])
            else if (next != null)
              Row(children: [
                const Icon(Icons.hourglass_bottom, size: 16),
                const SizedBox(width: 8),
                Text(fmtDuration(next.$1.difference(now)),
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(width: 8),
                Expanded(child: Text('${tr('kerahat_in')} · ${tr(next.$3)}')),
              ]),
          ],
          const SizedBox(height: 12),
          for (final w in windows)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                SizedBox(
                  width: 132,
                  child: Text(tr(w.$3), style: theme.textTheme.bodySmall),
                ),
                Text('${fmtTime(w.$1)} – ${fmtTime(w.$2)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _NextPrayerCard extends StatelessWidget {
  final DateTime now;
  const _NextPrayerCard({required this.now});

  @override
  Widget build(BuildContext context) {
    final next = appState.nextPrayer(now);
    final current = appState.currentPeriod(now);
    if (next == null) return const SizedBox.shrink();

    double progress = 0;
    if (current != null) {
      final total = next.value.difference(current.value).inSeconds;
      final done = now.difference(current.value).inSeconds;
      if (total > 0) progress = (done / total).clamp(0.0, 1.0);
    }

    final kerahatNow = appState.showKerahat ? appState.currentKerahat(now) : null;
    final kerahatNext = appState.showKerahat ? appState.nextKerahat(now) : null;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [pal.primary, pal.deep],
        ),
        border: Border.all(color: pal.gold.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('next_prayer').toUpperCase(),
              style: TextStyle(color: pal.gold, fontSize: 11, letterSpacing: 1.6)),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Icon(next.key.icon, color: pal.gold, size: 26),
            const SizedBox(width: 10),
            Text(next.key.label,
                style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text(fmtTime(next.value),
                style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w300)),
          ]),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation(pal.gold),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.hourglass_bottom, color: Colors.white70, size: 16),
            const SizedBox(width: 6),
            Text(fmtDuration(next.value.difference(now)),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()])),
            const SizedBox(width: 8),
            Text(tr('remaining'), style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ]),
          if (appState.showKerahat && (kerahatNow != null || kerahatNext != null)) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                Icon(
                  kerahatNow != null
                      ? Icons.warning_amber_rounded
                      : Icons.do_not_disturb_on_outlined,
                  size: 15,
                  color: kerahatNow != null ? const Color(0xFFE0A03A) : Colors.white70,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    kerahatNow != null
                        ? '${tr('kerahat_now')} · ${tr('kerahat_ends')} ${fmtDuration(kerahatNow.$2.difference(now))}'
                        : '${fmtDuration(kerahatNext!.$1.difference(now))} ${tr('kerahat_in')}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

class _PrayerRow extends StatelessWidget {
  final P p;
  final DayTimes day;
  final DateTime date, now;
  final bool isToday;
  const _PrayerRow({
    required this.p,
    required this.day,
    required this.date,
    required this.now,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCurrent = isToday && appState.currentPeriod(now)?.key == p;
    final done = p.isPrayer && appState.hasPrayed(date, p);

    return Container(
      decoration: BoxDecoration(
        color: isCurrent ? pal.gold.withValues(alpha: 0.12) : null,
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.only(left: 12, right: 4, top: 6, bottom: 6),
      child: Row(children: [
        Icon(p.icon, size: 20, color: isCurrent ? pal.gold : theme.colorScheme.outline),
        const SizedBox(width: 14),
        Expanded(
          child: Text(p.label,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500)),
        ),
        Text(fmtTime(day[p]),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
        if (p.isPrayer)
          IconButton(
            onPressed: () => appState.togglePrayed(date, p),
            icon: Icon(
              done ? Icons.check_circle : Icons.circle_outlined,
              color: done ? pal.accent : theme.colorScheme.outlineVariant,
            ),
          )
        else
          const SizedBox(width: 48),
      ]),
    );
  }
}

class _TrackerCard extends StatelessWidget {
  final DateTime now;
  const _TrackerCard({required this.now});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final week = appState.lastSevenDays;
    final today = appState.prayedCount(now);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.task_alt, size: 18, color: pal.gold),
            const SizedBox(width: 8),
            Text(tr('tracker'),
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const FriendsPage())),
              child: Text(tr('friends')),
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Text('$today / 5',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Text(tr('tracker_today'), style: theme.textTheme.bodySmall),
            const Spacer(),
            Icon(Icons.local_fire_department, size: 18, color: pal.gold),
            const SizedBox(width: 4),
            Text('${appState.streak} ${tr('days')}', style: theme.textTheme.bodyMedium),
          ]),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 7; i++)
                _DayBar(
                  count: week[i],
                  label: _weekdaysShort[appState.lang]![
                      now.subtract(Duration(days: 6 - i)).weekday - 1],
                  isToday: i == 6,
                ),
            ],
          ),
        ]),
      ),
    );
  }
}

class _DayBar extends StatelessWidget {
  final int count;
  final String label;
  final bool isToday;
  const _DayBar({required this.count, required this.label, required this.isToday});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(children: [
      Container(
        width: 26,
        height: 52,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: isToday ? Border.all(color: pal.gold, width: 1.4) : null,
        ),
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: (count / 5).clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              color: count >= 5 ? pal.gold : pal.accent,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text(label, style: theme.textTheme.labelSmall),
    ]);
  }
}

// =============================================================================
//  10. Freunde
// =============================================================================

class FriendsPage extends StatelessWidget {
  const FriendsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        final theme = Theme.of(context);
        final myWeek = appState.weekTotal;

        final rows = <(String, int, bool)>[
          (appState.userName.isEmpty ? tr('me') : appState.userName, myWeek, true),
          ...appState.friends.map((f) {
            final total = f.days.values.fold<int>(0, (a, b) => a + b);
            return (f.name, total, false);
          }),
        ]..sort((a, b) => b.$2.compareTo(a.$2));

        return Scaffold(
          appBar: AppBar(title: Text(tr('friends'))),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(tr('no_server_note'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(height: 1.5, color: theme.colorScheme.outline)),
              const SizedBox(height: 18),
              TextFormField(
                initialValue: appState.userName,
                decoration: InputDecoration(
                  labelText: tr('your_name'),
                  helperText: tr('name_hint'),
                ),
                onChanged: appState.setUserName,
              ),
              const SizedBox(height: 20),
              Text('${tr('week')} · ${tr('friends')}', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                child: Column(children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: rows[i].$3
                            ? pal.gold.withValues(alpha: 0.25)
                            : theme.colorScheme.surfaceContainerHighest,
                        child: Text('${i + 1}'),
                      ),
                      title: Text(rows[i].$1,
                          style: TextStyle(
                              fontWeight: rows[i].$3 ? FontWeight.w700 : FontWeight.w500)),
                      subtitle: Text('${rows[i].$2} / 35'),
                      trailing: rows[i].$3
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: tr('remove'),
                              onPressed: () => appState.removeFriend(rows[i].$1),
                            ),
                    ),
                  ],
                  if (appState.friends.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(tr('friends_none'),
                          textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                    ),
                ]),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => copyToClipboard(context, appState.buildShareCode()),
                icon: const Icon(Icons.ios_share),
                label: Text(tr('share_progress')),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => copyToClipboard(context, appState.buildInviteText()),
                icon: const Icon(Icons.person_add_alt),
                label: Text(tr('invite_friend')),
              ),
              const SizedBox(height: 20),
              Text(tr('add_friend'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _PasteFriendField(),
            ],
          ),
        );
      },
    );
  }
}

class _PasteFriendField extends StatefulWidget {
  @override
  State<_PasteFriendField> createState() => _PasteFriendFieldState();
}

class _PasteFriendFieldState extends State<_PasteFriendField> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: TextField(
          controller: _ctrl,
          maxLines: 2,
          decoration: InputDecoration(hintText: tr('paste_code_hint')),
        ),
      ),
      const SizedBox(width: 8),
      IconButton.filled(
        icon: const Icon(Icons.add),
        onPressed: () {
          final ok = appState.addFriendFromCode(_ctrl.text);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ok ? tr('saved') : tr('code_invalid'))),
          );
          if (ok) _ctrl.clear();
        },
      ),
    ]);
  }
}

// =============================================================================
//  11. Reiter 2 — Moscheen
// =============================================================================

class MosquesTab extends StatefulWidget {
  const MosquesTab({super.key});
  @override
  State<MosquesTab> createState() => _MosquesTabState();
}

class _MosquesTabState extends State<MosquesTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (appState.lat != null &&
          (appState.mosques.isEmpty || appState.mosquesStale)) {
        appState.loadMosques();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (appState.lat == null) {
      return ListView(children: [
        PageHeader(title: tr('mosques_title')),
        const LocationNotice(),
      ]);
    }

    final visible = appState.visibleMosques;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        PageHeader(
          title: tr('mosques_title'),
          subtitle: '${appState.locationLabel} · ${tr('radius')} ${appState.mosqueRadiusKm} ${tr('km')}',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Text('${tr('radius')}:', style: theme.textTheme.bodyMedium),
            const SizedBox(width: 10),
            for (final km in [2, 5, 10, 25])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text('$km'),
                  selected: appState.mosqueRadiusKm == km,
                  onSelected: (_) => appState.setMosqueRadius(km),
                ),
              ),
            const Spacer(),
            IconButton(
              onPressed: appState.mosquesLoading ? null : () => appState.loadMosques(),
              icon: const Icon(Icons.refresh),
              tooltip: tr('search_again'),
            ),
          ]),
        ),
        SwitchListTile(
          value: appState.onlySunni,
          onChanged: appState.setOnlySunni,
          title: Text(tr('only_sunni')),
          subtitle: Text(tr('only_sunni_hint'), style: theme.textTheme.bodySmall),
          secondary: const Icon(Icons.filter_alt_outlined),
        ),
        const SizedBox(height: 4),
        if (appState.mosquesLoading)
          Padding(
            padding: const EdgeInsets.all(30),
            child: Column(children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 14),
              Text(tr('mosques_loading')),
            ]),
          )
        else if (appState.mosqueError != null && visible.isEmpty)
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(children: [
              Icon(Icons.wifi_off, size: 40, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              Text(tr('mosques_offline'), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => appState.loadMosques(),
                icon: const Icon(Icons.refresh),
                label: Text(tr('retry')),
              ),
            ]),
          )
        else if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.all(28),
            child: Text(tr('mosques_none'), textAlign: TextAlign.center),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Card(
              child: Column(children: [
                for (var i = 0; i < visible.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _MosqueRow(m: visible[i]),
                ],
              ]),
            ),
          ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('mosques_times_note'),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
            const SizedBox(height: 8),
            Text(tr('mosques_source'),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
          ]),
        ),
      ],
    );
  }
}

class _MosqueRow extends StatelessWidget {
  final Mosque m;
  const _MosqueRow({required this.m});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = distanceKm(appState.lat!, appState.lng!, m.lat, m.lng);
    final isMine = appState.myMosque == m.name;
    final sub = [m.street, m.city].whereType<String>().where((s) => s.isNotEmpty).join(', ');

    return ListTile(
      leading: Icon(isMine ? Icons.star : Icons.mosque_outlined,
          color: isMine ? pal.gold : theme.colorScheme.outline),
      title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text([
        if (sub.isNotEmpty) sub,
        d < 1 ? '${(d * 1000).round()} m' : '${d.toStringAsFixed(1)} ${tr('km')}',
      ].join(' · ')),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => MosqueDetailPage(mosque: m))),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          switch (v) {
            case 'maps':
              openMaps(m.lat, m.lng, m.name);
            case 'call':
              if (m.phone != null) launchUrl(Uri.parse('tel:${m.phone}'));
            case 'ref':
              appState.setReferenceMosque(isMine ? null : m);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'ref', child: Text(tr('set_reference'))),
          PopupMenuItem(value: 'maps', child: Text(tr('route'))),
          if (m.phone != null) PopupMenuItem(value: 'call', child: Text(tr('call'))),
        ],
      ),
    );
  }
}

// =============================================================================
//  12. Reiter 3 — Qibla
// =============================================================================

class QiblaTab extends StatefulWidget {
  const QiblaTab({super.key});
  @override
  State<QiblaTab> createState() => _QiblaTabState();
}

class _QiblaTabState extends State<QiblaTab> {
  double? _heading;
  double? _accuracy;
  bool _wasAligned = false;
  bool _sensorMissing = false;
  StreamSubscription<CompassEvent>? _sub;

  static const double _tolerance = 3.0;

  /// 0 = weit weg, 1 = genau ausgerichtet. Ab 60° Abweichung bleibt es dunkel.
  double _glow(double? delta) {
    if (delta == null) return 0;
    final a = delta.abs();
    if (a <= _tolerance) return 1.0; // im Zielbereich volle Helligkeit
    final d = a.clamp(0.0, 60.0);
    final v = 1 - d / 60.0;
    return (v * v * 0.85).clamp(0.0, 0.85);
  }

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
        final smoothed =
            _heading == null ? h : (_heading! + Qibla.delta(_heading!, h) * 0.25 + 360) % 360;
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
    final dist = distanceKm(appState.lat!, appState.lng!, Qibla.kaabaLat, Qibla.kaabaLng);
    final heading = _heading;
    final delta = heading == null ? null : Qibla.delta(heading, bearing);
    final aligned = delta != null && delta.abs() <= _tolerance;

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
      statusColor = pal.gold;
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
        Center(
          child: SizedBox(
            width: 320,
            height: 320,
            child: Stack(alignment: Alignment.center, children: [
              // Lichtring: je näher an der Qibla, desto heller
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: pal.gold.withValues(alpha: 0.75 * _glow(delta)),
                      blurRadius: 24 + 56 * _glow(delta),
                      spreadRadius: 2 + 18 * _glow(delta),
                    ),
                    if (aligned)
                      BoxShadow(
                        color: pal.accent.withValues(alpha: 0.45),
                        blurRadius: 90,
                        spreadRadius: 12,
                      ),
                  ],
                ),
              ),
              Transform.rotate(
                angle: -((heading ?? 0) * math.pi / 180),
                child: CustomPaint(
                  size: const Size(320, 320),
                  painter: CompassDialPainter(
                    qiblaBearing: bearing,
                    onSurface: theme.colorScheme.onSurface,
                    outline: theme.colorScheme.outlineVariant,
                    gold: pal.gold,
                    surface: theme.brightness == Brightness.dark ? pal.surface : Colors.white,
                    deep: theme.brightness == Brightness.dark ? pal.deep : const Color(0xFFEDEBE4),
                  ),
                ),
              ),
              Transform.rotate(
                angle: ((bearing - (heading ?? 0)) * math.pi / 180),
                child: SizedBox(
                  width: 132,
                  height: 208,
                  child: CustomPaint(
                    painter: PrayerRugNeedlePainter(
                      aligned: aligned,
                      gold: pal.gold,
                      primary: pal.primary,
                      accent: pal.accent,
                    ),
                  ),
                ),
              ),
              Positioned(top: 0, child: Icon(Icons.arrow_drop_down, size: 34, color: pal.gold)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text('${bearing.toStringAsFixed(0)}° ${cardinalOf(bearing)}',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ),
        const SizedBox(height: 8),
        Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              color: aligned
                  ? pal.gold.withValues(alpha: 0.18)
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(aligned ? Icons.check_circle : Icons.rotate_right, size: 18, color: statusColor),
              const SizedBox(width: 8),
              Flexible(
                child: Text(status,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: statusColor, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ),
        if (_accuracy != null && _accuracy! > 20) ...[
          const SizedBox(height: 10),
          Center(child: Text(tr('calibrate_needed'), style: theme.textTheme.bodySmall)),
        ],
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.explore_outlined),
                title: Text(tr('qibla_title')),
                trailing: Text('${bearing.toStringAsFixed(1)}°', style: theme.textTheme.titleMedium),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.straighten),
                title: Text(tr('qibla_distance')),
                trailing:
                    Text('${dist.toStringAsFixed(0)} ${tr('km')}', style: theme.textTheme.titleMedium),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(tr('location')),
                subtitle: Text(appState.locationLabel),
                trailing: IconButton(
                  icon: const Icon(Icons.tune),
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const LocationPickerPage())),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class CompassDialPainter extends CustomPainter {
  final double qiblaBearing;
  final Color onSurface, outline, gold, surface, deep;

  CompassDialPainter({
    required this.qiblaBearing,
    required this.onSurface,
    required this.outline,
    required this.gold,
    required this.surface,
    required this.deep,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(colors: [surface, deep])
            .createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = gold.withValues(alpha: 0.5));
    canvas.drawCircle(
        center,
        radius - 26,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = outline.withValues(alpha: 0.6));

    for (var deg = 0; deg < 360; deg += 5) {
      final major = deg % 45 == 0;
      final rad = (deg - 90) * math.pi / 180;
      final dir = Offset(math.cos(rad), math.sin(rad));
      canvas.drawLine(
        center + dir * (radius - 2),
        center + dir * (radius - 2 - (major ? 14.0 : 6.0)),
        Paint()
          ..strokeWidth = major ? 2.0 : 1.0
          ..color = major ? onSurface.withValues(alpha: 0.7) : outline,
      );
    }

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

    final qRad = (qiblaBearing - 90) * math.pi / 180;
    final qPos = center + Offset(math.cos(qRad), math.sin(qRad)) * (radius - 15);
    canvas.save();
    canvas.translate(qPos.dx, qPos.dy);
    canvas.rotate(qiblaBearing * math.pi / 180);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 15, height: 15), const Radius.circular(2)),
      Paint()..color = const Color(0xFF141414),
    );
    canvas.drawLine(const Offset(-7.5, -2.5), const Offset(7.5, -2.5),
        Paint()..color = gold..strokeWidth = 2.2);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CompassDialPainter old) =>
      old.qiblaBearing != qiblaBearing || old.gold != gold || old.surface != surface;
}

class PrayerRugNeedlePainter extends CustomPainter {
  final bool aligned;
  final Color gold, primary, accent;
  PrayerRugNeedlePainter({
    required this.aligned,
    required this.gold,
    required this.primary,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    final rug = Path()
      ..moveTo(w * 0.08, h * 0.94)
      ..lineTo(w * 0.08, h * 0.36)
      ..cubicTo(w * 0.08, h * 0.10, w * 0.30, h * 0.03, w * 0.5, h * 0.03)
      ..cubicTo(w * 0.70, h * 0.03, w * 0.92, h * 0.10, w * 0.92, h * 0.36)
      ..lineTo(w * 0.92, h * 0.94)
      ..close();

    canvas.drawPath(
      rug.shift(const Offset(0, 4)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    canvas.drawPath(
      rug,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: aligned
              ? [accent, primary]
              : [primary, Color.lerp(primary, Colors.black, 0.45)!],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    canvas.drawPath(rug, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.4..color = gold);

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
          ..color = gold.withValues(alpha: 0.75));

    final mihrab = Path()
      ..moveTo(w * 0.30, h * 0.52)
      ..lineTo(w * 0.30, h * 0.36)
      ..cubicTo(w * 0.30, h * 0.22, w * 0.40, h * 0.19, w * 0.5, h * 0.19)
      ..cubicTo(w * 0.60, h * 0.19, w * 0.70, h * 0.22, w * 0.70, h * 0.36)
      ..lineTo(w * 0.70, h * 0.52)
      ..close();
    canvas.drawPath(mihrab, Paint()..color = Colors.white.withValues(alpha: 0.10));
    canvas.drawPath(
        mihrab,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = gold.withValues(alpha: 0.9));

    final cube =
        Rect.fromCenter(center: Offset(w * 0.5, h * 0.365), width: w * 0.17, height: w * 0.17);
    canvas.drawRRect(RRect.fromRectAndRadius(cube, const Radius.circular(1.5)),
        Paint()..color = const Color(0xFF0C0C0C));
    canvas.drawLine(
      Offset(cube.left, cube.top + cube.height * 0.34),
      Offset(cube.right, cube.top + cube.height * 0.34),
      Paint()..color = gold..strokeWidth = 1.6,
    );

    for (var i = 0; i < 3; i++) {
      final y = h * (0.62 + i * 0.09);
      canvas.drawLine(Offset(w * 0.26, y), Offset(w * 0.74, y),
          Paint()..color = gold.withValues(alpha: 0.35)..strokeWidth = 1.0);
    }

    for (var i = 0; i < 7; i++) {
      final x = w * (0.14 + i * 0.12);
      canvas.drawLine(
          Offset(x, h * 0.94),
          Offset(x, h * 0.99),
          Paint()
            ..color = gold.withValues(alpha: 0.8)
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round);
    }

    final tip = Path()
      ..moveTo(w * 0.5, -h * 0.035)
      ..lineTo(w * 0.42, h * 0.035)
      ..lineTo(w * 0.58, h * 0.035)
      ..close();
    canvas.drawPath(tip, Paint()..color = gold);
  }

  @override
  bool shouldRepaint(covariant PrayerRugNeedlePainter old) =>
      old.aligned != aligned || old.gold != gold || old.primary != primary;
}

// =============================================================================
//  13. Reiter 4 — Tesbih
// =============================================================================

class TasbihTab extends StatelessWidget {
  const TasbihTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = appState.tasbihTarget;
    final count = appState.tasbihCount;
    // Am Ziel bleibt die volle Zahl stehen statt auf 0 zu springen.
    final inRound = appState.tasbihAtTarget ? target : (target > 0 ? count % target : count % 33);
    final rounds = target > 0 ? count ~/ target : count ~/ 33;


    return Stack(children: [
      // Tippfläche liegt UNTER dem Inhalt, damit Knöpfe immer erreichbar bleiben.
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: MediaQuery.of(context).size.height / 3,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: appState.tasbihIncrement,
          child: const SizedBox.expand(),
        ),
      ),
      ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        PageHeader(title: tr('tasbih_title'), subtitle: tr('tap_anywhere')),
        const SizedBox(height: 8),
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
        Center(
          child: GestureDetector(
            onTap: appState.tasbihIncrement,
            onLongPress: appState.tasbihReset,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 300,
              height: 320,
              child: Stack(alignment: Alignment.center, children: [
                CustomPaint(
                  size: const Size(300, 320),
                  painter: TasbihPainter(
                    beadCount: (target > 33 || target == 0) ? 33 : target,
                    filled: appState.tasbihAtTarget
                        ? (target > 33 ? 33 : target)
                        : (target > 33 || target == 0 ? inRound % 33 : inRound),
                    gold: pal.gold,
                    bead: pal.primary,
                    accent: pal.accent,
                    shadow: pal.deep,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 26),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(appState.currentDhikr,
                        style: TextStyle(color: pal.gold, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text('$inRound',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 58,
                            fontWeight: FontWeight.w300,
                            height: 1.0)),
                    const SizedBox(height: 2),
                    Text(target == 0
                        ? '${tr('unlimited')} · ×$rounds'
                        : '${tr('tasbih_target')} $target · ×$rounds',
                        style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 26),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final t in [33, 99, 0])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(t == 0 ? tr('unlimited') : '$t'),
                selected: target == t,
                onSelected: (_) => appState.setTasbihTarget(t),
              ),
            ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: appState.tasbihReset,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(tr('tasbih_reset')),
          ),
        ]),
        if (appState.tasbihAtTarget) ...[
          const SizedBox(height: 14),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: pal.gold.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_circle, size: 16, color: pal.gold),
                const SizedBox(width: 8),
                Text('${tr('target_reached')} · $target',
                    style: TextStyle(color: pal.gold, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(motivationOfTheDay(DateTime.now()),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
        ),
        const SizedBox(height: 120),
      ],
      ),
    ]);
  }
}

// =============================================================================
//  14. Reiter 5 — Mehr
// =============================================================================

class MoreTab extends StatelessWidget {
  const MoreTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('tab_more'))),
      body: ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        PageHeader(title: tr('tab_more')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: Text(tr('tab_settings')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const SettingsPage())),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: Text(tr('friends')),
                subtitle: Text('${appState.friends.length}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const FriendsPage())),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(tr('location')),
                subtitle: Text(appState.locationLabel),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const LocationPickerPage())),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.calculate_outlined),
              title: Text(tr('zakat_calculator')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const ZakatPage())),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.no_food_outlined),
              title: Text(tr('fasting_tracker')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const FastingTrackerPage())),
            ),
            ]),
          ),
        ),
        const SizedBox(height: 26),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('settings_about').toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary)),
            const SizedBox(height: 8),
            Text(tr('about_body'),
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.55)),
          ]),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text('Nur Islam · 4.0.0',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
        ),
      ],
      ),
    );
  }
}

// =============================================================================
//  15. Einstellungen
// =============================================================================

/// Gemerkter Zustand der Einstellungen: welcher Bereich offen war und wie weit
/// gescrollt wurde. Wird beim bewussten Zurück oben links geleert.
String? _openSettingsSection;
double _settingsScroll = 0;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final ScrollController _scroll =
      ScrollController(initialScrollOffset: _settingsScroll);

  @override
  void dispose() {
    if (_scroll.hasClients) _settingsScroll = _scroll.offset;
    _scroll.dispose();
    super.dispose();
  }

  void _leave() {
    _openSettingsSection = null;
    _settingsScroll = 0;
    Navigator.pop(context);
  }

  Widget _section(String id, String title, IconData icon, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: ExpansionTile(
        key: PageStorageKey(id),
        initiallyExpanded: _openSettingsSection == id ||
            (_openSettingsSection == null && id == 'appearance'),
        onExpansionChanged: (open) => _openSettingsSection = open ? id : null,
        leading: Icon(icon, color: pal.gold),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        children: children,
      ),
    );
  }

  Widget _minutesRow(String label, int value, ValueChanged<int> onChanged) => ListTile(
        dense: true,
        title: Text(label),
        subtitle: Text('$value ${tr('minutes')}'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () => onChanged(value - 5),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => onChanged(value + 5),
          ),
        ]),
      );

  Future<void> _pickMethod() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('method')),
        contentPadding: const EdgeInsets.only(top: 12),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final m in kMethods)
                RadioListTile<String>(
                  value: m.id,
                  groupValue: appState.methodId,
                  onChanged: (v) {
                    appState.applyMethod(v!);
                    Navigator.pop(context);
                  },
                  title: Text(m.name, style: const TextStyle(fontSize: 14)),
                  subtitle: Text(
                    m.ishaInterval > 0
                        ? '${m.fajr}° · ${tr('isha_interval')} ${m.ishaInterval} ${tr('minutes')}'
                        : '${m.fajr}° / ${m.isha}°'
                            '${m.asr == 2 ? ' · ${tr('asr_second')}' : ''}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              if (appState.methodId == 'custom')
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: Text(tr('method_custom')),
                  subtitle: Text('${appState.fajrAngle.toStringAsFixed(1)}° / '
                      '${appState.ishaAngle.toStringAsFixed(1)}°'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        final theme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(
            title: Text(tr('tab_settings')),
            leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _leave),
          ),
          body: ListView(
            controller: _scroll,
            padding: const EdgeInsets.only(top: 12, bottom: 40),
            children: [
              // --- Sprache und Darstellung ---
              _section('appearance', tr('settings_appearance'), Icons.palette_outlined, [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: SegmentedButton<AppLang>(
                    segments: const [
                      ButtonSegment(value: AppLang.de, label: Text('DE')),
                      ButtonSegment(value: AppLang.tr, label: Text('TR')),
                      ButtonSegment(value: AppLang.en, label: Text('EN')),
                    ],
                    selected: {appState.lang},
                    onSelectionChanged: (s) => appState.setLang(s.first),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(tr('settings_palette'),
                        style: theme.textTheme.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final entry in palettes.entries)
                        _PaletteChip(value: entry.key, data: entry.value),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  value: appState.use24h,
                  onChanged: appState.setUse24h,
                  title: Text(tr('settings_time_format')),
                  secondary: const Icon(Icons.access_time),
                ),
              ]),

              // --- Widgets ---
              _section('widgets', tr('widgets'), Icons.widgets_outlined, [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(tr('widget_hint'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(height: 1.4, color: theme.colorScheme.outline)),
                ),
                ListTile(
                  dense: true,
                  title: Text(tr('widget_alpha')),
                  subtitle: Text('${(appState.widgetAlpha / 255 * 100).round()} %'),
                ),
                Slider(
                  value: appState.widgetAlpha.toDouble(),
                  min: 40,
                  max: 255,
                  divisions: 43,
                  onChanged: (v) => appState.setWidgetAlpha(v.round()),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(tr('widget_refresh_note'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(height: 1.4, color: theme.colorScheme.outline)),
                ),
              ]),

              // --- Benachrichtigungen (noch gesperrt) ---
              Card(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: ListTile(
                  enabled: false,
                  leading: Icon(Icons.notifications_none, color: pal.gold),
                  title: Text(tr('notifications')),
                  subtitle: Text('${tr('coming_soon')} · ${tr('notifications_locked')}'),
                  trailing: Icon(Icons.lock, size: 18, color: pal.gold),
                ),
              ),

              // --- Zeitquelle ---
              _section('source', tr('time_source'), Icons.source_outlined, [
                RadioListTile<TimeSource>(
                  value: TimeSource.calculated,
                  groupValue: appState.timeSource,
                  onChanged: (v) => appState.setTimeSource(v!),
                  title: Text(tr('src_calc')),
                  subtitle: Text(tr('src_calc_sub')),
                ),
                RadioListTile<TimeSource>(
                  value: TimeSource.online,
                  groupValue: appState.timeSource,
                  onChanged: (v) {
                    appState.setTimeSource(v!);
                    appState.syncOnline();
                  },
                  title: Text(tr('src_online')),
                  subtitle: Text(tr('src_online_sub')),
                ),
                if (appState.timeSource == TimeSource.online)
                  ListTile(
                    dense: true,
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
                              final ok = await appState.syncOnline();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text(ok ? tr('sync_ok') : tr('sync_failed'))));
                              }
                            },
                            child: Text(tr('sync_now')),
                          ),
                  ),
                RadioListTile<TimeSource>(
                  value: TimeSource.custom,
                  groupValue: appState.timeSource,
                  onChanged: (v) => appState.setTimeSource(v!),
                  title: Text(tr('src_custom')),
                  subtitle: Text(tr('src_custom_sub')),
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.edit_note),
                  title: Text(tr('custom_table')),
                  subtitle: Text('${tr('stored_days')}: ${appState.customTimes.length}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const CustomTablePage())),
                ),
              ]),

              // --- Berechnung ---
              _section('calc', tr('settings_calculation'), Icons.calculate_outlined, [
                ListTile(
                  leading: const Icon(Icons.public),
                  title: Text(tr('method')),
                  subtitle: Text(appState.methodId == 'custom'
                      ? tr('method_custom')
                      : appState.method.name),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickMethod,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(tr('method_hint'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                ),
                ListTile(
                  leading: const Icon(Icons.wb_sunny_outlined),
                  title: Text(tr('asr_method')),
                  subtitle:
                      Text(appState.asrShadowFactor == 1 ? tr('asr_first') : tr('asr_second')),
                  trailing: Switch(
                    value: appState.asrShadowFactor == 2,
                    onChanged: (v) {
                      appState.setAsrFactor(v ? 2 : 1);
                      if (appState.timeSource == TimeSource.online) appState.syncOnline();
                    },
                  ),
                ),
                SwitchListTile(
                  value: appState.useTemkin,
                  onChanged: appState.setUseTemkin,
                  secondary: const Icon(Icons.timer_outlined),
                  title: Text(tr('temkin')),
                  subtitle: Text(tr('temkin_hint')),
                ),
                ListTile(
                  leading: const Icon(Icons.brightness_4_outlined),
                  title: Text(tr('angles')),
                  subtitle: Text(appState.ishaIntervalMin > 0
                      ? '${appState.fajrAngle.toStringAsFixed(1)}° · '
                          '${tr('isha_interval')} ${appState.ishaIntervalMin} ${tr('minutes')}'
                      : '${appState.fajrAngle.toStringAsFixed(1)}° / '
                          '${appState.ishaAngle.toStringAsFixed(1)}°'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const AnglesPage())),
                ),
              ]),

              // --- Kerahat ---
              _section('kerahat', tr('kerahat'), Icons.do_not_disturb_on_outlined, [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(tr('kerahat_hint'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                ),
                SwitchListTile(
                  value: appState.showKerahat,
                  onChanged: appState.setShowKerahat,
                  secondary: const Icon(Icons.visibility_outlined),
                  title: Text(tr('kerahat_show')),
                ),
                if (appState.showKerahat) ...[
                  _minutesRow(tr('k_israk'), appState.kerahatSunriseMin,
                      (v) => appState.setKerahatMinutes(sunrise: v)),
                  _minutesRow(tr('k_istiva'), appState.kerahatIstivaMin,
                      (v) => appState.setKerahatMinutes(istiva: v)),
                  _minutesRow(tr('k_isfirar'), appState.kerahatSunsetMin,
                      (v) => appState.setKerahatMinutes(sunset: v)),
                ],
              ]),

              // --- Feinjustierung ---
              _section('offsets', tr('settings_offsets'), Icons.tune, [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(tr('settings_offsets_hint'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                ),
                for (final p in P.values)
                  ListTile(
                    dense: true,
                    leading: Icon(p.icon, size: 20),
                    title: Text(p.label),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => appState.setOffset(p, (appState.offsets[p] ?? 0) - 1),
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
                        onPressed: () => appState.setOffset(p, (appState.offsets[p] ?? 0) + 1),
                      ),
                    ]),
                  ),
              ]),

              // --- Standort ---
              _section('location', tr('location'), Icons.place_outlined, [
                ListTile(
                  leading: Icon(appState.manualLocation ? Icons.push_pin : Icons.my_location),
                  title: Text(appState.manualLocation ? tr('loc_manual') : tr('loc_auto')),
                  subtitle: Text(appState.locationLabel),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const LocationPickerPage())),
                ),
              ]),
            ],
          ),
        );
      },
    );
  }
}

class _PaletteChip extends StatelessWidget {
  final AppPalette value;
  final PaletteData data;
  const _PaletteChip({required this.value, required this.data});

  @override
  Widget build(BuildContext context) {
    final selected = appState.palette == value;
    final name = switch (appState.lang) {
      AppLang.de => data.nameDe,
      AppLang.tr => data.nameTr,
      AppLang.en => data.nameEn,
    };
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => appState.setPalette(value),
      child: Container(
          width: 108,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? data.gold : Theme.of(context).colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              for (final c in [data.deep, data.primary, data.gold, data.accent])
                Container(
                  width: 18,
                  height: 26,
                  margin: const EdgeInsets.only(right: 3),
                  decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
                ),
            ]),
            const SizedBox(height: 8),
            Text(name, style: const TextStyle(fontSize: 11), maxLines: 2),
          ]),
      ),
    );
  }
}

// =============================================================================
//  16. Dämmerungswinkel und Kalibrierung
// =============================================================================

class AnglesPage extends StatefulWidget {
  const AnglesPage({super.key});
  @override
  State<AnglesPage> createState() => _AnglesPageState();
}

class _AnglesPageState extends State<AnglesPage> {
  final _fajrCtrl = TextEditingController();
  final _ishaCtrl = TextEditingController();

  @override
  void dispose() {
    _fajrCtrl.dispose();
    _ishaCtrl.dispose();
    super.dispose();
  }

  /// Rechnet aus einer eingegebenen Uhrzeit den zugehörigen Sonnenwinkel.
  double? _angleFromTime(String input) {
    if (appState.lat == null) return null;
    final m = RegExp(r'^\s*(\d{1,2})[:.](\d{2})\s*$').firstMatch(input);
    if (m == null) return null;
    final now = DateTime.now();
    final t = DateTime(now.year, now.month, now.day, int.parse(m.group(1)!), int.parse(m.group(2)!));
    final alt = PrayerCalculator.altitudeAt(t, appState.lat!, appState.lng!);
    if (alt > -5 || alt < -25) return null;
    return -alt;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(tr('angles'))),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(tr('angles_hint'), style: theme.textTheme.bodySmall?.copyWith(height: 1.5)),
            const SizedBox(height: 20),
            _slider(
              label: '${tr('fajr_angle')}: ${appState.fajrAngle.toStringAsFixed(1)}°',
              value: appState.fajrAngle,
              onChanged: (v) => appState.setAngles(fajr: v),
            ),
            _slider(
              label: '${tr('isha_angle')}: ${appState.ishaAngle.toStringAsFixed(1)}°',
              value: appState.ishaAngle,
              onChanged: (v) => appState.setAngles(isha: v),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => appState.applyMethod('diyanet'),
                  child: const Text('Diyanet: 14,9° / 13,9°'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => appState.setAngles(fajr: 18, isha: 17),
                  child: const Text('Klassisch: 18° / 17°'),
                ),
              ),
            ]),
            const SizedBox(height: 26),
            Text(tr('calibrate'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(tr('calibrate_hint'), style: theme.textTheme.bodySmall?.copyWith(height: 1.5)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _fajrCtrl,
                  decoration: InputDecoration(labelText: tr('p_fajr'), hintText: '04:07'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _ishaCtrl,
                  decoration: InputDecoration(labelText: tr('p_isha'), hintText: '22:58'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                final f = _angleFromTime(_fajrCtrl.text);
                final i = _angleFromTime(_ishaCtrl.text);
                if (f == null && i == null) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(tr('calibrate_failed'))));
                  return;
                }
                appState.setAngles(fajr: f, isha: i);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('${tr('calibrated')}: '
                      '${appState.fajrAngle.toStringAsFixed(1)}° / '
                      '${appState.ishaAngle.toStringAsFixed(1)}°'),
                ));
              },
              icon: const Icon(Icons.tune),
              label: Text(tr('calibrate')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label),
      Slider(
        value: value,
        min: 10,
        max: 20,
        divisions: 100,
        label: value.toStringAsFixed(1),
        onChanged: onChanged,
      ),
    ]);
  }
}

// =============================================================================
//  17. Standort wählen
// =============================================================================

class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage({super.key});
  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  final _searchCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  List<(String, double, double)> _results = [];
  bool _searching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (appState.lat != null) {
      _latCtrl.text = appState.lat!.toStringAsFixed(5);
      _lngCtrl.text = appState.lng!.toStringAsFixed(5);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
      _results = [];
    });
    try {
      final r = await appState.searchPlace(q);
      setState(() => _results = r);
      if (r.isEmpty) setState(() => _error = tr('no_results'));
    } catch (_) {
      setState(() => _error = tr('no_results'));
    }
    if (mounted) setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('choose_manually'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.my_location),
              title: Text(tr('loc_auto')),
              trailing: FilledButton(
                onPressed: () async {
                  await appState.refreshLocation();
                  if (context.mounted && appState.locState == LocState.ready) {
                    Navigator.pop(context);
                  }
                },
                child: Text(tr('apply')),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(tr('search_place'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(hintText: tr('search_hint')),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: _search, icon: const Icon(Icons.search)),
          ]),
          const SizedBox(height: 12),
          if (_searching)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Text(tr('searching')),
              ]),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          for (final r in _results)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(r.$1, maxLines: 2, style: const TextStyle(fontSize: 13)),
                onTap: () async {
                  await appState.setManualLocation(r.$2, r.$3, r.$1);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ),
          const SizedBox(height: 20),
          Text(tr('coords_manual'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _latCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: InputDecoration(labelText: tr('latitude')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _lngCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: InputDecoration(labelText: tr('longitude')),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () async {
                  final la = double.tryParse(_latCtrl.text.replaceAll(',', '.'));
                  final lo = double.tryParse(_lngCtrl.text.replaceAll(',', '.'));
                  if (la == null || lo == null || la.abs() > 90 || lo.abs() > 180) return;
                  await appState.setManualLocation(la, lo, null);
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.check),
                label: Text(tr('apply')),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: () {
                final la = double.tryParse(_latCtrl.text.replaceAll(',', '.'));
                final lo = double.tryParse(_lngCtrl.text.replaceAll(',', '.'));
                if (la != null && lo != null) openMaps(la, lo);
              },
              icon: const Icon(Icons.map_outlined, size: 18),
              label: Text(tr('open_in_maps')),
            ),
          ]),
          const SizedBox(height: 12),
          Text(tr('maps_tip'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
        ],
      ),
    );
  }
}

// =============================================================================
//  18. Eigene Zeiten einfügen
// =============================================================================

// ============================================================
// Zakat-Rechner
// ============================================================
class ZakatPage extends StatefulWidget {
  const ZakatPage({super.key});
  @override
  State<ZakatPage> createState() => _ZakatPageState();
}

class _ZakatPageState extends State<ZakatPage> {
  final _cashCtrl = TextEditingController();
  final _goldGCtrl = TextEditingController();
  final _goldPCtrl = TextEditingController();
  final _silverGCtrl = TextEditingController();
  final _silverPCtrl = TextEditingController();
  final _otherCtrl = TextEditingController();
  final _debtCtrl = TextEditingController();
  bool _basisGold = true;
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    _prefs = p;
    _cashCtrl.text = p.getString('zakat_cash') ?? '';
    _goldGCtrl.text = p.getString('zakat_gold_g') ?? '';
    _goldPCtrl.text = p.getString('zakat_gold_p') ?? '75';
    _silverGCtrl.text = p.getString('zakat_silver_g') ?? '';
    _silverPCtrl.text = p.getString('zakat_silver_p') ?? '0.9';
    _otherCtrl.text = p.getString('zakat_other') ?? '';
    _debtCtrl.text = p.getString('zakat_debt') ?? '';
    _basisGold = p.getBool('zakat_basis_gold') ?? true;
    if (mounted) setState(() {});
  }

  void _save() {
    final p = _prefs;
    if (p == null) return;
    p.setString('zakat_cash', _cashCtrl.text);
    p.setString('zakat_gold_g', _goldGCtrl.text);
    p.setString('zakat_gold_p', _goldPCtrl.text);
    p.setString('zakat_silver_g', _silverGCtrl.text);
    p.setString('zakat_silver_p', _silverPCtrl.text);
    p.setString('zakat_other', _otherCtrl.text);
    p.setString('zakat_debt', _debtCtrl.text);
    p.setBool('zakat_basis_gold', _basisGold);
  }

  double _n(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.')) ?? 0;

  @override
  void dispose() {
    _cashCtrl.dispose();
    _goldGCtrl.dispose();
    _goldPCtrl.dispose();
    _silverGCtrl.dispose();
    _silverPCtrl.dispose();
    _otherCtrl.dispose();
    _debtCtrl.dispose();
    super.dispose();
  }

  Widget _field(TextEditingController c, String labelKey, {String suffix = '€'}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: tr(labelKey),
          suffixText: suffix,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) {
          _save();
          setState(() {});
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        final theme = Theme.of(context);
        final cash = _n(_cashCtrl);
        final goldG = _n(_goldGCtrl);
        final goldP = _n(_goldPCtrl);
        final silverG = _n(_silverGCtrl);
        final silverP = _n(_silverPCtrl);
        final other = _n(_otherCtrl);
        final debt = _n(_debtCtrl);

        final rawTotal = cash + goldG * goldP + silverG * silverP + other - debt;
        final totalAssets = rawTotal < 0 ? 0.0 : rawTotal;
        final nisab = _basisGold ? 85 * goldP : 595 * silverP;
        final due = (nisab > 0 && totalAssets >= nisab) ? totalAssets * 0.025 : 0.0;

        String money(double v) => '${v.toStringAsFixed(2)} €';

        return Scaffold(
          appBar: AppBar(title: Text(tr('zakat_calculator'))),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(tr('zakat_intro'), style: theme.textTheme.bodyMedium),
              const SizedBox(height: 20),
              _field(_cashCtrl, 'zakat_cash'),
              _field(_goldGCtrl, 'zakat_gold_grams', suffix: 'g'),
              _field(_goldPCtrl, 'zakat_gold_price'),
              _field(_silverGCtrl, 'zakat_silver_grams', suffix: 'g'),
              _field(_silverPCtrl, 'zakat_silver_price'),
              _field(_otherCtrl, 'zakat_other_assets'),
              _field(_debtCtrl, 'zakat_debts'),
              const SizedBox(height: 8),
              Text(tr('zakat_nisab_basis'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: true, label: Text(tr('zakat_basis_gold'))),
                  ButtonSegment(value: false, label: Text(tr('zakat_basis_silver'))),
                ],
                selected: {_basisGold},
                onSelectionChanged: (s) {
                  _basisGold = s.first;
                  _save();
                  setState(() {});
                },
              ),
              const SizedBox(height: 24),
              Card(
                color: pal.gold.withValues(alpha: 0.12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(tr('zakat_total_assets')),
                      Text(money(totalAssets)),
                    ]),
                    const SizedBox(height: 6),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(tr('zakat_nisab_value')),
                      Text(money(nisab)),
                    ]),
                    const Divider(height: 20),
                    if (due > 0)
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text(tr('zakat_result_due'), style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text(money(due), style: TextStyle(fontWeight: FontWeight.bold, color: pal.gold, fontSize: 18)),
                      ])
                    else
                      Text(tr('zakat_result_not_due')),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              Text(tr('zakat_disclaimer'),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================
// Fasten-Tracker
// ============================================================
class FastingTrackerPage extends StatelessWidget {
  const FastingTrackerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        final theme = Theme.of(context);
        final today = DateTime.now();
        final fastedToday = appState.hasFasted(today);
        final streak = appState.fastingStreak;
        final monthCount = appState.fastedThisMonth;

        return Scaffold(
          appBar: AppBar(title: Text(tr('fasting_tracker'))),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(tr('fasting_intro'), style: theme.textTheme.bodyMedium),
              const SizedBox(height: 20),
              Card(
                child: SwitchListTile(
                  title: Text(tr('fasting_today')),
                  value: fastedToday,
                  onChanged: (_) => appState.toggleFasted(today),
                  secondary: Icon(Icons.no_food_outlined, color: pal.gold),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        Text('$streak', style: theme.textTheme.headlineMedium
                            ?.copyWith(color: pal.gold, fontWeight: FontWeight.bold)),
                        Text(
                            '${tr('fasting_streak')} (${tr('fasting_days_suffix')})',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        Text('$monthCount', style: theme.textTheme.headlineMedium
                            ?.copyWith(color: pal.gold, fontWeight: FontWeight.bold)),
                        Text(tr('fasting_month_count'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall),
                      ]),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 24),
              Text(tr('fasting_last_days'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(35, (i) {
                  final d = today.subtract(Duration(days: 34 - i));
                  final done = appState.hasFasted(d);
                  return GestureDetector(
                    onTap: () => appState.toggleFasted(d),
                    child: Container(
                      width: 36,
                      height: 44,
                      decoration: BoxDecoration(
                        color: done ? pal.gold.withValues(alpha: 0.85) : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('${d.day}',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: done ? Colors.black : theme.colorScheme.onSurface)),
                        if (done) const Icon(Icons.check, size: 12, color: Colors.black),
                      ]),
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}

class CustomTablePage extends StatefulWidget {
  const CustomTablePage({super.key});
  @override
  State<CustomTablePage> createState() => _CustomTablePageState();
}

class _CustomTablePageState extends State<CustomTablePage> {
  final _ctrl = TextEditingController();
  late int _month = DateTime.now().month;
  late int _year = DateTime.now().year;
  int? _parsedCount;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('custom_table'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(tr('custom_paste_hint'), style: theme.textTheme.bodySmall?.copyWith(height: 1.5)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _month,
                decoration: InputDecoration(labelText: tr('month')),
                items: [
                  for (var m = 1; m <= 12; m++)
                    DropdownMenuItem(value: m, child: Text(_months[appState.lang]![m - 1])),
                ],
                onChanged: (v) => setState(() => _month = v ?? _month),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _year,
                decoration: InputDecoration(labelText: tr('year')),
                items: [
                  for (var y = DateTime.now().year - 1; y <= DateTime.now().year + 2; y++)
                    DropdownMenuItem(value: y, child: Text('$y')),
                ],
                onChanged: (v) => setState(() => _year = v ?? _year),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            maxLines: 12,
            minLines: 8,
            decoration: const InputDecoration(
              hintText: '01  04:23  06:13  13:38  17:29  20:52  22:32\n'
                  '02  04:25  06:14  13:38  17:28  20:50  22:30\n…',
            ),
            onChanged: (v) =>
                setState(() => _parsedCount = TableParser.parse(v, _year, _month).length),
          ),
          const SizedBox(height: 10),
          if (_parsedCount != null)
            Text('${tr('parsed_days')}: $_parsedCount',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _parsedCount! > 0 ? theme.colorScheme.primary : theme.colorScheme.error,
                )),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async {
              final table = TableParser.parse(_ctrl.text, _year, _month);
              if (table.isEmpty) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(tr('nothing_parsed'))));
                return;
              }
              await appState.saveCustomTable(table);
              appState.setTimeSource(TimeSource.custom);
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('${tr('saved')}: ${table.length}')));
                Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.save_outlined),
            label: Text(tr('save')),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: appState.customTimes.isEmpty
                ? null
                : () async {
                    await appState.clearCustomTable();
                    if (context.mounted) setState(() {});
                  },
            icon: const Icon(Icons.delete_outline),
            label: Text('${tr('clear_table')} (${appState.customTimes.length})'),
          ),
        ],
      ),
    );
  }
}


/// Gebetskette: Perlen im Kreis, gefüllt bis zum aktuellen Stand,
/// mit Imame (Kopfperle) und Quaste unten.
class TasbihPainter extends CustomPainter {
  final int beadCount, filled;
  final Color gold, bead, accent, shadow;
  TasbihPainter({
    required this.beadCount,
    required this.filled,
    required this.gold,
    required this.bead,
    required this.accent,
    required this.shadow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 14);
    final radius = size.width / 2 - 26;
    final count = beadCount < 1 ? 1 : beadCount;

    // Perlen sitzen auf einem Bogen von 320 Grad, unten bleibt Platz für die Imame.
    const sweep = 320.0;
    const startDeg = -160.0;
    final step = sweep / count;
    final beadR = (2 * math.pi * radius * (sweep / 360) / count) / 2.4;

    // Schnur
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      (startDeg - 90) * math.pi / 180,
      sweep * math.pi / 180,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = gold.withValues(alpha: 0.35),
    );

    for (var i = 0; i < count; i++) {
      final deg = startDeg + step * i + step / 2;
      final rad = (deg - 90) * math.pi / 180;
      final c = center + Offset(math.cos(rad), math.sin(rad)) * radius;
      final isDone = i < filled;
      final isNext = i == filled;

      canvas.drawCircle(
        c.translate(0, 2),
        beadR,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.30)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );

      canvas.drawCircle(
        c,
        beadR,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.4, -0.5),
            colors: isDone
                ? [Color.lerp(gold, Colors.white, 0.45)!, gold]
                : [Color.lerp(bead, Colors.white, 0.18)!, shadow],
          ).createShader(Rect.fromCircle(center: c, radius: beadR)),
      );

      canvas.drawCircle(
        c,
        beadR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isNext ? 1.8 : 0.8
          ..color = isNext ? accent : gold.withValues(alpha: 0.45),
      );

      // Glanzpunkt
      canvas.drawCircle(
        c.translate(-beadR * 0.3, -beadR * 0.35),
        beadR * 0.22,
        Paint()..color = Colors.white.withValues(alpha: isDone ? 0.55 : 0.25),
      );
    }

    // Imame unten
    final imameTop = center + Offset(0, radius - beadR * 0.4);
    final imameRect = Rect.fromCenter(
      center: imameTop.translate(0, beadR * 1.5),
      width: beadR * 1.7,
      height: beadR * 3.4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(imameRect, Radius.circular(beadR * 0.85)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(gold, Colors.white, 0.35)!, gold],
        ).createShader(imameRect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(imameRect, Radius.circular(beadR * 0.85)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = shadow.withValues(alpha: 0.5),
    );

    // Quaste
    final tasselTop = imameRect.bottomCenter;
    for (var i = -3; i <= 3; i++) {
      canvas.drawLine(
        tasselTop,
        tasselTop.translate(i * 2.4, 22 - (i.abs() * 2.0)),
        Paint()
          ..color = gold.withValues(alpha: 0.75)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant TasbihPainter old) =>
      old.filled != filled || old.beadCount != beadCount || old.gold != gold;
}

// =============================================================================
//  19. Moschee als Zeitquelle
// =============================================================================

/// Wird über den kleinen Knopf oben rechts im Zeiten-Reiter geöffnet.
class MosqueSourcePage extends StatelessWidget {
  const MosqueSourcePage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        final theme = Theme.of(context);
        final current = appState.refMosque;
        final nearby = appState.visibleMosques;

        return Scaffold(
          appBar: AppBar(title: Text(tr('times_from'))),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (current != null)
                Card(
                  child: Column(children: [
                    ListTile(
                      leading: Icon(Icons.mosque, color: pal.gold),
                      title: Text(current.name,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(current.address.isEmpty
                          ? tr('mosque_active')
                          : current.address),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: Text(tr('mosque_info')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => MosqueDetailPage(mosque: current))),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.location_off_outlined),
                      title: Text(tr('clear_mosque')),
                      onTap: () => appState.setReferenceMosque(null),
                    ),
                  ]),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(tr('mosque_times_explain'),
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.5)),
                ),
              const SizedBox(height: 20),
              Text(tr('change_mosque'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              if (nearby.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(tr('mosques_none'), textAlign: TextAlign.center),
                )
              else
                Card(
                  child: Column(children: [
                    for (var i = 0; i < nearby.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        leading: Icon(
                          nearby[i].name == current?.name
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: nearby[i].name == current?.name ? pal.gold : null,
                        ),
                        title: Text(nearby[i].name),
                        subtitle: Text(
                          '${distanceKm(appState.lat!, appState.lng!, nearby[i].lat, nearby[i].lng).toStringAsFixed(1)} ${tr('km')}',
                        ),
                        onTap: () {
                          appState.setReferenceMosque(nearby[i]);
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ]),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Alles zu einer einzelnen Moschee: Infos, Anrufen, Weg, Zeiten übernehmen.
class MosqueDetailPage extends StatelessWidget {
  final Mosque mosque;
  const MosqueDetailPage({super.key, required this.mosque});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        final theme = Theme.of(context);
        final isActive = appState.refMosque?.name == mosque.name;
        final d = appState.lat == null
            ? null
            : distanceKm(appState.lat!, appState.lng!, mosque.lat, mosque.lng);

        return Scaffold(
          appBar: AppBar(title: Text(mosque.name, overflow: TextOverflow.ellipsis)),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: pal.gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle, size: 16, color: pal.gold),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(tr('mosque_active'),
                          style: theme.textTheme.labelMedium?.copyWith(color: pal.gold)),
                    ),
                  ]),
                ),
              const SizedBox(height: 16),

              // Schnellzugriff
              Row(children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: mosque.phone == null
                        ? null
                        : () => launchUrl(Uri.parse('tel:${mosque.phone}')),
                    icon: const Icon(Icons.call, size: 18),
                    label: Text(tr('call')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => launchUrl(
                      Uri.parse(
                          'https://www.google.com/maps/dir/?api=1&destination=${mosque.lat},${mosque.lng}'),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.directions, size: 18),
                    label: Text(tr('route')),
                  ),
                ),
              ]),
              const SizedBox(height: 20),

              Card(
                child: Column(children: [
                  ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: Text(mosque.address.isEmpty ? tr('no_info') : mosque.address),
                    subtitle: d == null ? null : Text('${d.toStringAsFixed(1)} ${tr('km')}'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.schedule_outlined),
                    title: Text(tr('opening_hours')),
                    subtitle: Text(mosque.openingHours ?? tr('no_info')),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.phone_outlined),
                    title: Text(mosque.phone ?? tr('no_info')),
                    onTap: mosque.phone == null
                        ? null
                        : () => launchUrl(Uri.parse('tel:${mosque.phone}')),
                  ),
                  if (mosque.website != null) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.language),
                      title: Text(tr('website')),
                      subtitle: Text(mosque.website!, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => launchUrl(Uri.parse(mosque.website!),
                          mode: LaunchMode.externalApplication),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 22),

              FilledButton.icon(
                onPressed: () {
                  appState.setReferenceMosque(isActive ? null : mosque);
                  if (!isActive) Navigator.pop(context);
                },
                icon: Icon(isActive ? Icons.link_off : Icons.link),
                label: Text(isActive ? tr('clear_mosque') : tr('use_this_mosque')),
              ),
              const SizedBox(height: 12),
              Text(tr('mosque_times_explain'),
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.5)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const CustomTablePage())),
                icon: const Icon(Icons.edit_note, size: 18),
                label: Text(tr('enter_jamaat')),
              ),
              const SizedBox(height: 20),
              Text(tr('mosques_source'),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
//  20. Hidschri-Kalender und besondere Tage
// =============================================================================

class Hijri {
  final int year, month, day;
  const Hijri(this.year, this.month, this.day);

  /// Umrechnung nach dem tabellarischen Verfahren. Kann um einen Tag abweichen.
  static Hijri fromDate(DateTime date) {
    int d = date.day, m = date.month, y = date.year;
    int jd;
    if ((y > 1582) || (y == 1582 && m > 10) || (y == 1582 && m == 10 && d > 14)) {
      jd = ((1461 * (y + 4800 + ((m - 14) ~/ 12))) ~/ 4) +
          ((367 * (m - 2 - 12 * ((m - 14) ~/ 12))) ~/ 12) -
          ((3 * ((y + 4900 + ((m - 14) ~/ 12)) ~/ 100)) ~/ 4) +
          d - 32075;
    } else {
      jd = 367 * y -
          ((7 * (y + 5001 + ((m - 9) ~/ 7))) ~/ 4) +
          ((275 * m) ~/ 9) + d + 1729777;
    }
    int l = jd - 1948440 + 10632;
    final n = (l - 1) ~/ 10631;
    l = l - 10631 * n + 354;
    final j = ((10985 - l) ~/ 5316) * ((50 * l) ~/ 17719) + (l ~/ 5670) * ((43 * l) ~/ 15238);
    l = l - ((30 - j) ~/ 15) * ((17719 * j) ~/ 50) - (j ~/ 16) * ((15238 * j) ~/ 43) + 29;
    final mm = (24 * l) ~/ 709;
    final dd = l - ((709 * mm) ~/ 24);
    final yy = 30 * n + j - 30;
    return Hijri(yy, mm, dd);
  }

  static const List<String> monthsTr = [
    'Muharrem', 'Safer', 'Rebiülevvel', 'Rebiülahir', 'Cemaziyelevvel', 'Cemaziyelahir',
    'Recep', 'Şaban', 'Ramazan', 'Şevval', 'Zilkade', 'Zilhicce',
  ];

  String get label => '$day ${monthsTr[(month - 1).clamp(0, 11)]} $year';
}

/// Ein besonderer Tag im islamischen Kalender.
class SpecialDay {
  final String nameDe, nameTr, nameEn;
  final int hijriMonth, hijriDay, lengthDays;
  final bool major; // Bayram und Ramazan werden kräftiger markiert
  const SpecialDay(this.nameDe, this.nameTr, this.nameEn, this.hijriMonth, this.hijriDay,
      {this.lengthDays = 1, this.major = false});

  String get name => switch (appState.lang) {
        AppLang.de => nameDe,
        AppLang.tr => nameTr,
        AppLang.en => nameEn,
      };
}

const List<SpecialDay> kSpecialDays = [
  SpecialDay('Islamisches Neujahr', 'Hicri Yılbaşı', 'Islamic New Year', 1, 1),
  SpecialDay('Aschura', 'Aşure Günü', 'Ashura', 1, 10),
  SpecialDay('Mevlid-Nacht', 'Mevlid Kandili', 'Mawlid', 3, 12),
  SpecialDay('Mirac-Nacht', 'Miraç Kandili', 'Isra and Miraj', 7, 27),
  SpecialDay('Berat-Nacht', 'Berat Kandili', 'Mid-Sha\'ban', 8, 15),
  SpecialDay('Ramadan', 'Ramazan', 'Ramadan', 9, 1, lengthDays: 29, major: true),
  SpecialDay('Nacht der Bestimmung', 'Kadir Gecesi', 'Laylat al-Qadr', 9, 27),
  SpecialDay('Ramadanfest', 'Ramazan Bayramı', 'Eid al-Fitr', 10, 1, lengthDays: 3, major: true),
  SpecialDay('Arafat-Tag', 'Arefe', 'Day of Arafah', 12, 9),
  SpecialDay('Opferfest', 'Kurban Bayramı', 'Eid al-Adha', 12, 10, lengthDays: 4, major: true),
];

/// Welcher besondere Tag fällt auf dieses Datum? Gibt zusätzlich zurück, ob es
/// der erste bzw. letzte Tag eines mehrtägigen Zeitraums ist.
({SpecialDay day, bool first, bool last})? specialFor(DateTime date) {
  final h = Hijri.fromDate(date);
  for (final e in kSpecialDays) {
    if (e.hijriMonth != h.month) continue;
    final offset = h.day - e.hijriDay;
    if (offset >= 0 && offset < e.lengthDays) {
      return (day: e, first: offset == 0, last: offset == e.lengthDays - 1);
    }
  }
  return null;
}

/// Zuletzt betrachteter Monat, damit der Kalender dort wieder aufgeht.
DateTime? _rememberedMonth;

class CalendarPage extends StatefulWidget {
  final DateTime initial;
  const CalendarPage({super.key, required this.initial});
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _month =
      _rememberedMonth ?? DateTime(widget.initial.year, widget.initial.month);

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _rememberedMonth = _month;
    });
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = first.weekday - 1; // Montag = 0
    final cells = <DateTime?>[
      ...List.filled(leading, null),
      ...List.generate(daysInMonth, (i) => DateTime(_month.year, _month.month, i + 1)),
    ];
    final today = DateTime.now();

    final monthEvents = <String, SpecialDay>{};
    for (var i = 1; i <= daysInMonth; i++) {
      final sp = specialFor(DateTime(_month.year, _month.month, i));
      if (sp != null) monthEvents[sp.day.name] = sp.day;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('calendar')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _rememberedMonth = null; // bewusstes Zurück löscht die Erinnerung
            Navigator.pop(context);
          },
        ),
      ),
      body: GestureDetector(
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -250) _shiftMonth(1);
          if (v > 250) _shiftMonth(-1);
        },
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            IconButton(
              onPressed: () => _shiftMonth(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Column(children: [
                Text('${_months[appState.lang]![_month.month - 1]} ${_month.year}',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text(Hijri.fromDate(DateTime(_month.year, _month.month, 15)).label,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.outline)),
              ]),
            ),
            IconButton(
              onPressed: () => _shiftMonth(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ]),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final w in _weekdaysShort[appState.lang]!)
                Expanded(
                  child: Center(
                    child: Text(w,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.78,
            ),
            itemCount: cells.length,
            itemBuilder: (context, i) {
              final d = cells[i];
              if (d == null) return const SizedBox.shrink();
              final sp = specialFor(d);
              final isToday = d.year == today.year && d.month == today.month && d.day == today.day;
              final isSelected = d.year == widget.initial.year &&
                  d.month == widget.initial.month &&
                  d.day == widget.initial.day;
              return _CalendarCell(
                date: d,
                special: sp,
                isToday: isToday,
                isSelected: isSelected,
                onTap: () {
                  _rememberedMonth = _month;
                  Navigator.pop(context, d);
                },
              );
            },
          ),
          const SizedBox(height: 20),
          if (monthEvents.isNotEmpty) ...[
            Text(tr('special_days'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Card(
              child: Column(children: [
                for (final e in monthEvents.values)
                  ListTile(
                    dense: true,
                    leading: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: e.major ? pal.gold : pal.accent,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    title: Text(e.name),
                    subtitle: e.lengthDays > 1
                        ? Text('${e.lengthDays} ${tr('days')}')
                        : null,
                  ),
              ]),
            ),
            const SizedBox(height: 14),
          ],
          Text(tr('hijri_note'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(height: 1.5, color: theme.colorScheme.outline)),
          const SizedBox(height: 10),
          Text(tr('swipe_hint'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline)),
        ],
      ),
      ),
    );
  }
}

class _CalendarCell extends StatelessWidget {
  final DateTime date;
  final ({SpecialDay day, bool first, bool last})? special;
  final bool isToday, isSelected;
  final VoidCallback onTap;
  const _CalendarCell({
    required this.date,
    required this.special,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sp = special;
    final multi = sp != null && sp.day.lengthDays > 1;
    final colour = sp == null ? null : (sp.day.major ? pal.gold : pal.accent);

    // Mehrtägige Zeiträume bekommen ein durchgehendes Band,
    // damit man sofort sieht, dass die Tage zusammengehören.
    final radius = BorderRadius.horizontal(
      left: Radius.circular(multi && !sp.first ? 0 : 10),
      right: Radius.circular(multi && !sp.last ? 0 : 10),
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: multi ? 0 : 2, vertical: 2),
        decoration: BoxDecoration(
          color: colour?.withValues(alpha: multi ? 0.20 : 0.28),
          borderRadius: radius,
          border: isSelected
              ? Border.all(color: theme.colorScheme.primary, width: 1.6)
              : (isToday ? Border.all(color: pal.gold, width: 1.2) : null),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${date.day}',
                style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: isToday || sp != null ? FontWeight.w700 : FontWeight.w400)),
            Text('${Hijri.fromDate(date).day}',
                style: theme.textTheme.labelSmall
                    ?.copyWith(fontSize: 9, color: theme.colorScheme.outline)),
            if (sp != null && !multi)
              Container(
                margin: const EdgeInsets.only(top: 2),
                width: 5,
                height: 5,
                decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
//  21. Community
// =============================================================================

class CommunityPage extends StatelessWidget {
  const CommunityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(tr('tab_community'),
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5)),
          ),
        ),
        TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: pal.gold,
          indicatorColor: pal.gold,
          tabs: [
            Tab(text: tr('sub_friends'), icon: const Icon(Icons.groups_outlined, size: 16)),
            Tab(text: tr('sub_news'), icon: const Icon(Icons.lock_outline, size: 16)),
            Tab(text: tr('sub_meet'), icon: const Icon(Icons.lock_outline, size: 16)),
            Tab(text: tr('sub_qa'), icon: const Icon(Icons.lock_outline, size: 16)),
          ],
        ),
        Expanded(
          child: TabBarView(children: [
            const FriendsFeed(),
            _LockedPane(text: tr('news_locked')),
            _LockedPane(text: tr('meet_locked')),
            _LockedPane(text: tr('qa_locked_body')),
          ]),
        ),
      ]),
    );
  }
}

class _LockedPane extends StatelessWidget {
  final String text;
  const _LockedPane({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const SizedBox(height: 30),
        Center(
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.surfaceContainerHighest,
              border: Border.all(color: pal.gold.withValues(alpha: 0.6), width: 1.5),
            ),
            child: Icon(Icons.lock_outline, size: 42, color: pal.gold),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
              color: pal.gold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(tr('coming_soon'),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700, color: pal.gold)),
          ),
        ),
        const SizedBox(height: 18),
        Text(text, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(height: 1.55)),
      ],
    );
  }
}

/// Freundes-Feed mit Durchschnitten und Rangliste.
class FriendsFeed extends StatelessWidget {
  const FriendsFeed({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final rows = <({String name, int week, int month, bool me})>[
      (
        name: appState.userName.isEmpty ? tr('me') : appState.userName,
        week: appState.weekTotal,
        month: appState.monthTotal,
        me: true,
      ),
      ...appState.friends.map((f) => (
            name: f.name,
            week: f.totalOver(7),
            month: f.totalOver(30),
            me: false,
          )),
    ]..sort((a, b) => b.month.compareTo(a.month));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        // Eigene Zahlen
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('avg_week'), style: theme.textTheme.labelMedium),
                  const SizedBox(height: 4),
                  Text('${appState.weekAverage.toStringAsFixed(1)} ${tr('per_day')}',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                ]),
              ),
              Container(width: 1, height: 38, color: theme.colorScheme.outlineVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('avg_month'), style: theme.textTheme.labelMedium),
                  const SizedBox(height: 4),
                  Text('${appState.monthAverage.toStringAsFixed(1)} ${tr('per_day')}',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 18),
        Text(tr('ranking'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Card(
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _RankRow(rank: i + 1, row: rows[i]),
            ],
            if (appState.friends.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(tr('friends_none'),
                    textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
              ),
          ]),
        ),
        const SizedBox(height: 20),
        Text(tr('my_code'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(tr('my_code_hint'),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
        if (appState.userName.trim().isEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: pal.gold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              Icon(Icons.person_outline, size: 16, color: pal.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr('name_needed'),
                    style: theme.textTheme.bodySmall?.copyWith(color: pal.gold)),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 6),
        SelectableText(appState.buildShareCode(),
            style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(height: 4),
        Text(tr('code_length_note'),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () => copyToClipboard(context, appState.buildInviteText()),
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: Text(tr('invite_friend')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => copyToClipboard(context, appState.buildShareCode()),
              icon: const Icon(Icons.ios_share, size: 18),
              label: Text(tr('share_progress')),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const FriendsPage())),
          icon: const Icon(Icons.settings_outlined, size: 18),
          label: Text(tr('friends')),
        ),
        const SizedBox(height: 18),
        Text(tr('no_server_note'),
            style: theme.textTheme.bodySmall
                ?.copyWith(height: 1.5, color: theme.colorScheme.outline)),
      ],
    );
  }
}

class _RankRow extends StatelessWidget {
  final int rank;
  final ({String name, int week, int month, bool me}) row;
  const _RankRow({required this.rank, required this.row});

  static const Color gold = Color(0xFFD4AF37);
  static const Color silver = Color(0xFFB9BFC7);
  static const Color bronze = Color(0xFFB07A45);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final medal = switch (rank) {
      1 => gold,
      2 => silver,
      3 => bronze,
      _ => null,
    };

    return ListTile(
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: medal?.withValues(alpha: 0.22) ?? theme.colorScheme.surfaceContainerHighest,
          border: medal == null ? null : Border.all(color: medal, width: 1.6),
        ),
        alignment: Alignment.center,
        child: Text('$rank',
            style: TextStyle(
                fontWeight: FontWeight.w700, color: medal ?? theme.colorScheme.onSurface)),
      ),
      title: Text(row.name,
          style: TextStyle(fontWeight: row.me ? FontWeight.w700 : FontWeight.w500)),
      subtitle: Text('${tr('week')}: ${row.week} · 30 ${tr('days')}: ${row.month}'),
      trailing: Text('${(row.month / 30).toStringAsFixed(1)}',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
    );
  }
}

// =============================================================================
//  22. Tutorial beim ersten Start
// =============================================================================

class OnboardingDialog extends StatefulWidget {
  const OnboardingDialog({super.key});
  @override
  State<OnboardingDialog> createState() => _OnboardingDialogState();
}

class _OnboardingDialogState extends State<OnboardingDialog> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    ('tut1_t', 'tut1_b', Icons.nightlight_round),
    ('tut2_t', 'tut2_b', Icons.swipe),
    ('tut3_t', 'tut3_b', Icons.mosque_outlined),
    ('tut4_t', 'tut4_b', Icons.explore_outlined),
    ('tut5_t', 'tut5_b', Icons.groups_outlined),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    appState.finishTutorial();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLast = _page == _pages.length - 1;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        height: 430,
        child: Column(children: [
          Expanded(
            child: PageView.builder(
              controller: _controller,
              onPageChanged: (i) => setState(() => _page = i),
              itemCount: _pages.length,
              itemBuilder: (context, i) {
                final p = _pages[i];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(28, 34, 28, 10),
                  child: Column(children: [
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [pal.primary, pal.deep]),
                        border: Border.all(color: pal.gold.withValues(alpha: 0.6)),
                      ),
                      child: Icon(p.$3, size: 42, color: pal.gold),
                    ),
                    const SizedBox(height: 22),
                    Text(tr(p.$1),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    Text(tr(p.$2),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                  ]),
                );
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _pages.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i == _page ? pal.gold : theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(children: [
              TextButton(onPressed: _finish, child: Text(tr('skip'))),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  if (isLast) {
                    _finish();
                  } else {
                    _controller.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    );
                  }
                },
                child: Text(isLast ? tr('start') : tr('next')),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
