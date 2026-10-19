<p align="center">
  <img src="assets/Temada.png" alt="Temada logosi" width="112" />
</p>

<h1 align="center">Temada</h1>
<p align="center">Suhbatni kuzating. Tarjimani tushuning.</p>
<p align="center"><b>macOS 14+ · EN / RU / UZ · Rust + Swift</b></p>

> 🧪 **Sinov versiyasi.** Real uchrashuvdagi aniqlik, tezlik va barcha ilovalarda ishlash hali to‘liq tasdiqlanmagan.

## ✨ Nima qiladi?

| | Imkoniyat |
|---|---|
| 🎧 | Meet, Zoom, video va boshqa ilovalarning **tizim ovozidan** transkript va tarjima. |
| 🎙️ | Mikrofon yoki tizim ovozi; **Both** — ikkalasi birga. |
| 💬 | Kichik oynada asl matn va tarjima; tarixni yuqoriga scroll qilib o‘qing. |
| ⌨️ | O‘zbekcha gapiring → inglizcha matnni kursor turgan joyga kiriting. Shortcutni o‘zingiz tanlang. |
| 📝 | Uchrashuv matnini **JSONL + Markdown** fayllariga saqlang. |
| 🎨 | Shrift, rang va oyna o‘lchamini moslang. Trayda Temada logosi. |

**Model yuklab olish shart emas.** Audio Google Gemini API orqali qayta ishlanadi; internet kerak.

## 🚀 Boshlash

1. **Temada → Settings** ni oching, Gemini API key kiriting.
2. **Audio** manbasi va tarjima tilini tanlang.
3. **Request access** orqali kerakli macOS ruxsatlarini bering, **Check again** bosing.
4. Cloud/API xarajatlari roziligini belgilang → **Start captions**.
5. Tugatish uchun tray menyusidan **Stop captions** bosing.

💡 **Both** uchun quloqchin tavsiya etiladi: aks-sado va takroriy matn kamayadi.

### ⌨️ Ovozdan inglizcha matn

**Settings → Uzbek → English at your cursor → Record shortcut… → Enable.**
Mikrofon va Accessibility ruxsati kerak. Matn maydoniga kursor qo‘ying, shortcutni bosing,
**Listening** holatini kutib gapiring; tugatish uchun yana bosing. Send/Enter bosilmaydi.
macOS band qilgan shortcutlar va ayrim matn maydonlari ishlamasligi mumkin.

## 🔒 Maxfiylik va xarajatlar

- **Gemini API alohida hisoblanadi** — ChatGPT/Gemini obunasi API xarajatlarini qoplamaydi. Bepul ishlashi kafolatlanmaydi.
- Audio Googlega yuboriladi. Eshitilmaydigan yaratilgan audio ham hisoblanishi mumkin; **Both** ikki sessiya ochadi. Ishtirokchilar roziligini oling.
- API key faqat shu ishga tushirish davomida xotirada turadi; ilovani qayta ochganda yana kiritasiz.
- Audio diskka yozilmaydi. **Meeting files** bo‘limida saqlash yoqilgan bo‘lsa, matn shifrlanmagan fayllarda saqlanadi — xususiy papka tanlang.
- Tarmoq, kvota yoki xavfsizlik limitlari sessiyani to‘xtatishi mumkin. Tarjima va jumlalar mosligi kafolatlanmaydi.

<details>
<summary>🛠️ Yig‘ish, cheklovlar va testlar — kerak bo‘lsa oching</summary>

### Manbadan yig‘ish

macOS 14+, Xcode Command Line Tools, Rust/Cargo va mavjud tasdiqlangan Apple Development sertifikati kerak.
Buyruqlarni repo ildizida bajaring; sertifikat SHA-1 o‘rinbosarini almashtiring:

```sh
export MC_CODESIGN_IDENTITY="YOUR_APPROVED_CERTIFICATE_40_HEX_SHA1"
bash scripts/build-native.sh
open "dist/Temada.app"
```

Build mavjud `.app` ustiga yozmaydi; yangi chiqish yo‘li uchun `MC_NATIVE_APP` belgilang.
Yangilashdan oldin foydalanuvchi roziligi bilan faqat Temada’ni yoping, zaxiralang va imzosini tekshiring.
Bir xil sertifikat, `dev.bro.mclbb` identifikatori va barqaror o‘rnatish yo‘lini saqlang.
Ad-hoc imzo qabul qilinmaydi; sertifikat/trust sozlamalari o‘zgartirilmaydi. Build notarizatsiya qilinmagan.

### Ishlash va xavfsizlik

- **Arxitektura:** SwiftUI/AppKit interfeys, Rust backend, ScreenCaptureKit/AVAudioEngine audio.
  Model: `gemini-3.5-live-translate-preview`. Account/hududga qarab mavjudlik farqlanadi; avtomatik boshqa model/providerga o‘tmaydi.
- **Audio:** 16kHz mono PCM16, ko‘pi bilan 100 ms freymlar. Tizim ovozi birinchi display orqali barcha ilovalardan olinadi, faqat Meet/Zoom emas; ekran tasviri saqlanmaydi. Mikrofon — macOS standart qurilmasi; echo cancellation yo‘q.
- **Ruxsat:** manbaga mos macOS ruxsatlari va har ishga tushirishda yangi cloud roziligi kerak. Ochish/ruxsat berish o‘zi yozishni boshlamaydi. Key/manba/til/saqlash sozlamalari o‘zgarsa, rozilik bekor bo‘ladi. TCC chetlab o‘tilmaydi; macOS qayta tasdiq so‘rashi mumkin.
- **API key:** native ilova `.env` yuklamaydi. Key xotirada, faqat rozilikdan so‘ng private stdin orqali workerga beriladi; argv, environment, log yoki Keychain’ga yozilmaydi. Bootstrap 4096 bayt, key 1024 ASCII bayt bilan cheklangan. OS swap/crash dumpdan himoya yoki kriptografik zeroization kafolati yo‘q.
- **Uzoq sessiya:** uchrashuv uchun 10 daqiqalik sun’iy limit yo‘q. Faqat server GoAway va yaroqli xotiradagi handle bilan davom etadi; har manba uchun 60 s ichida 3 urinish, setup 12 s, yuborish 2 s. Qayta ulanishda 128 freym / 128000 PCM bayt (~4s) RAM bufer; oshsa yashirin yo‘qotish o‘rniga to‘xtaydi. Quota/auth/network xatolari ko‘r-ko‘rona qayta urinilmaydi.
- **Cheklovlar:** capture 20 s / server 60 s watchdog, bounded UI/navbatlar va javob hajmi limitlari saqlanadi. Resumption checkpoint’i nutqni yo‘qotmasdan/takrorsiz tiklash kafolati emas. Uzluksiz uptime yoki pul sarfi limiti kafolatlanmaydi; jimlik ham API ishlatishi mumkin.
- **Scroll:** to‘liq matn saqlanadi; yuqoriga scroll kuzatishni to‘xtatadi, pastki 6 pt hududga qaytish davom ettiradi. Tarix 16 MiB / 10000 qator; alignment cache 48 qator, pending limit 64. Limitda eski matn yashirin o‘chirilmaydi — capture to‘xtaydi. Clear/Quit xotira tarixini tozalaydi; turli manbalar aralashtirilmaydi, semantik jumla mosligi kafolatlanmaydi.
- **Fayllar:** default `~/Library/Application Support/Temada/Meetings`. Har uchrashuv alohida 0700 papka, `meeting.jsonl` va `meeting.md` 0600 fayllari; private/exclusive yozish, mavjud fayl almashtirilmaydi. Navbat 1 MiB, jurnal 16 MiB. Status/xatolar/key/audio yozilmaydi. Cloud-synced papka yoki OS backup fayllarni tashqariga ko‘chirishi mumkin; o‘chirish foydalanuvchiga bog‘liq.
- **Stop/Quit:** faqat o‘z helper/socketlari yopiladi; final pipe freymlari va fayl yozilishi kutiladi. 8 s ichida Quit tugamasa yoki saqlash xatosi bo‘lsa, Quit bekor qilinadi; boshqa ilovalar force-kill qilinmaydi. Crash/to‘la diskda pending yozuv yoki Markdown yo‘qolishi mumkin. Bu lossless recorder emas; Stop tugallanmagan nutqni tashlashi mumkin.
- **Dictation:** faqat alohida Enable va tugma bosishdan keyin; meeting bilan birga ishlamaydi. 60 s yozish + 15 s final-turn kutish, har matn oqimi 16000 UTF-8 bayt. Faqat muvaffaqiyatli final turn va o‘sha xavfsiz caret’da bitta AX insertion; cancellation/error/early/interrupted/empty turn matn kiritmaydi. Password, selection, terminal, o‘zgargan focus/caret va mos kelmagan maydonlar rad etiladi. AX tekshiruvi atomik focus-lock emas; draft faqat qo‘lda Copy uchun xotirada, meeting fayliga kirmaydi.
- **Shortcut:** ⌘/⌃/⌥ + key, ixtiyoriy Shift yoki F1–F20; default ⇧⌘Space. Oddiy/Shift-only harflar va modifier-only bind yo‘q. Faqat fokusdagi recorder vaqtincha local event’ni oladi; global keyboard monitor/Input Monitoring yoki OS shortcut o‘zgarishi yo‘q. Escape/focus yo‘qolishi yozishni bekor qiladi; bind saqlanadi, arming saqlanmaydi. macOS band qilgan kombinatsiyalar ishlamasligi mumkin.
- **Legacy:** `scripts/build.sh` alohida eski egui ilovasini yig‘adi, native Temada emas. Uning Live rejimida optional `.env` aliaslari `GEMINI_API_KEY`/`GOOGLE_API_KEY` (64 KiB, shell ishlatmaydi). Eksperimental CLI rejimi 4 s vaqtinchalik WAV ishlatadi, realtime emas; Gemini/Codex/AGY obunasi orqali audio ishlashi tasdiqlanmagan, crash’da temp fayl qolishi mumkin. Native ilova bu yo‘lga yashirin o‘tmaydi.

### Tekshirish va holat

```sh
bash scripts/test.sh
bash scripts/test-native.sh
# Tasdiqlangan sertifikat bilan; Keychain so‘rovini faqat foydalanuvchi tasdiqlaydi:
bash scripts/test-signing.sh
```

Oxirgi kod tekshiruvlari: **44 Rust test PASS, 1 real-cloud test ataylab ignored**;
fmt/strict Clippy, synthetic audio, native UI/history/files/permissions/shortcut va imzo testlari PASS.
Authenticated setup-only probe audiosiz o‘tgan; bu real uchrashuv testi emas.
Real Meet/Zoom/Both, TCC/AX/global shortcut, tarjima aniqligi, latency/smoothness,
uzoq sessiya va preview model/account qo‘llovi hali manual acceptance talab qiladi.
Original Python/local STT routing va frozen **P0–P5** mezonlari o‘zgartirilmagan/yakunlanmagan.

Eski bosqichma-bosqich hisobotlar Git tarixida va Plane’da saqlangan; takroriy hujjatlar olib tashlangan.
[Gemini Live Translate](https://ai.google.dev/gemini-api/docs/live-api/live-translate) ·
[Live sessions](https://ai.google.dev/gemini-api/docs/live-session) ·
[API narxlari va ma’lumot siyosati](https://ai.google.dev/gemini-api/docs/pricing)

</details>
