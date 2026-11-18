# ============================================================
#  OLIMP ZAGOTOVKA - CHEK AGENTI  (USB printer uchun)
#  Telegramda "Tayyor" bosilganda zayavka ro'yxatini chek printerida chiqaradi.
#  Printer monoblokka USB bilan ulangan -- IP manzil KERAK EMAS.
#
#  SINOV.bat        - chek ko'rinishi (printerga yuborilmaydi)
#  PRINTERLAR.bat   - o'rnatilgan printerlar ro'yxati
#  ISHGA_TUSHIRISH.bat - ishga tushirish
#
#  --- 2026-11-18 o'zgarishlari (v2) -------------------------------------
#  1. OCHIQ LINIYA. Avval har 4 soniyada "chek bormi?" deb so'rardi, ya'ni
#     chek 0-4,5 soniya kutib qolardi. Endi so'rovga `wait` qo'shiladi:
#     bulut javobni darhol bermay, chekni 12 soniyagacha KUTIB turadi va
#     chek paydo bo'lishi bilan o'sha ochiq liniyadan darhol jo'natadi.
#     Natija: chek "Tayyor" bosilgandan keyin ~1 soniyada chiqadi, ustiga
#     bulutga so'rov soni kuniga ~21 600 dan ~7 000 ga tushadi.
#  2. PRINTER NOMI QAT'IY. Avval nomi bo'yicha avtomat tanlardi; agar
#     termal printer topilmasa Windowsning STANDART printeriga o'tardi --
#     u esa bu monoblokda Canon lazerniki. Endi avval aniq "XP-Q80A"
#     qidiriladi va lazernikka tushib qolsa logda QALIN ogohlantirish.
#  3. "CHIQDI" DEGANI ROSTDAN CHIQQAN BO'LSIN. Avval WritePrinter "ha"
#     desa yetarli deb bilinardi -- lekin printer o'chiq bo'lsa ham
#     Windows ma'lumotni qabul qilaveradi va chek YO'QOLARDI. Endi:
#     yuborishdan oldin printer holati tekshiriladi (offline / qog'oz
#     tugagan / qopqoq ochiq), yuborgandan keyin esa spooler navbati
#     kuzatiladi. Muammo bo'lsa chek "chiqdi" deb BELGILANMAYDI -- u
#     bulut navbatida qoladi va printer tuzalganda o'zi chiqadi.
# ============================================================
param(
  [string]$PrinterName = "",
  [string]$Key = "",
  [switch]$Test,
  [switch]$ListPrinters
)

$ENDPOINT = "https://zagotovka-zayavka-send.olimpzagotovka.workers.dev/print/poll"
# Ochiq liniya javobdan keyin darhol qayta so'raladi -- bu faqat kichik
# nafas (bulut xato bersa cheksiz aylanmaslik uchun).
$INTERVAL = 0.3
# Bulut liniyani 12 soniyagacha ushlaydi, zahira bilan 30 soniya qo'yamiz.
$TIMEOUT  = 30
$LOG      = Join-Path $PSScriptRoot "chek_log.txt"
# Ekrandagi kichik ko'rsatkich (chek_ekran.ps1) shu fayldan o'qiydi.
# Har aylanishda yangilanadi -- fayl eskirib qolsa, demak agent to'xtagan.
$HOLAT_FAYL = Join-Path $PSScriptRoot "chek_holat.txt"
$KENGLIK  = 48   # oddiy shriftda 80 mm = 48 belgi
$KENG_KATTA = 24 # ikki barobar kengaytirilgan shriftda = 24 belgi
# Printer nomi berilmasa birinchi navbatda shu qidiriladi.
$KUTILGAN_PRINTER = "XP-Q80A"
# Bu so'zlar printer nomida chiqsa -- bu termal chek printeri EMAS.
$LAZERNIK = "Canon|LBP|Laser|HP |Kyocera|Samsung|Xerox|PDF|XPS|OneNote|Fax"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Yoz($matn) {
  $qator = "{0}  {1}" -f (Get-Date -Format "dd.MM HH:mm:ss"), $matn
  Write-Host $qator
  try { Add-Content -Path $LOG -Value $qator -Encoding UTF8 } catch {}
}

# --- RAW chop etish: ESC/POS baytlarini to'g'ridan-to'g'ri printerga ---
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class RawPrint {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct DOCINFO { [MarshalAs(UnmanagedType.LPWStr)] public string pDocName;
                          [MarshalAs(UnmanagedType.LPWStr)] public string pOutputFile;
                          [MarshalAs(UnmanagedType.LPWStr)] public string pDataType; }
  [DllImport("winspool.drv", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern bool OpenPrinter(string src, out IntPtr hPrinter, IntPtr pd);
  [DllImport("winspool.drv", SetLastError=true)] public static extern bool ClosePrinter(IntPtr hPrinter);
  [DllImport("winspool.drv", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern bool StartDocPrinter(IntPtr hPrinter, int level, ref DOCINFO di);
  [DllImport("winspool.drv", SetLastError=true)] public static extern bool EndDocPrinter(IntPtr hPrinter);
  [DllImport("winspool.drv", SetLastError=true)] public static extern bool StartPagePrinter(IntPtr hPrinter);
  [DllImport("winspool.drv", SetLastError=true)] public static extern bool EndPagePrinter(IntPtr hPrinter);
  [DllImport("winspool.drv", SetLastError=true)]
  public static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, int dwCount, out int dwWritten);

  public static string Send(string printer, byte[] data) {
    IntPtr h = IntPtr.Zero;
    if (!OpenPrinter(printer, out h, IntPtr.Zero)) return "printer ochilmadi (OpenPrinter)";
    try {
      DOCINFO di = new DOCINFO();
      di.pDocName = "Zayavka chek"; di.pDataType = "RAW";
      if (!StartDocPrinter(h, 1, ref di)) return "StartDocPrinter xato";
      if (!StartPagePrinter(h)) { EndDocPrinter(h); return "StartPagePrinter xato"; }
      IntPtr buf = Marshal.AllocCoTaskMem(data.Length);
      Marshal.Copy(data, 0, buf, data.Length);
      int yozildi = 0;
      bool ok = WritePrinter(h, buf, data.Length, out yozildi);
      Marshal.FreeCoTaskMem(buf);
      EndPagePrinter(h); EndDocPrinter(h);
      if (!ok) return "WritePrinter xato";
      return "";
    } finally { ClosePrinter(h); }
  }
}
"@

# --- ESC/POS buyruqlari ---
$E = [char]27
$G = [char]29
$INIT      = $E + "@"
$CP866     = $E + "t" + [char]17
$MARKAZ    = $E + "a" + [char]1
$CHAP      = $E + "a" + [char]0
$QALIN_ON  = $E + "E" + [char]1
$QALIN_OFF = $E + "E" + [char]0
$KATTA     = $G + "!" + [char]17   # 2x en + 2x boy (sarlavha)
$BALAND    = $G + "!" + [char]1    # 2x BOY, en o'zgarmaydi -> 48 belgi saqlanadi
$ODDIY     = $G + "!" + [char]0
$KES       = $G + "V" + [char]66 + [char]3

function ChekQatorlar($ish) {
  $chiziq = "-" * $KENGLIK
  $q = @()
  $q += "ZAYAVKA"
  $q += [string]$ish.source
  $q += $chiziq
  $q += "Kimga : " + [string]$ish.dest
  $q += "Yozgan: " + [string]$ish.login
  $q += "Sana  : " + [string]$ish.when
  $q += $chiziq
  # 2026-10-08: mahsulot qatorlari IKKI BAROBAR KENG shriftda -- 24 belgi.
  # 2026-10-08 (egasi so'rovi): mahsulot nomi ASL HOLICHA qoladi -- hech narsa
  # olib tashlanmaydi va KESILMAYDI. Nom sig'masa so'zlar bo'yicha keyingi
  # qatorga o'tkaziladi, miqdor esa oxirida o'ngga tortiladi.
  foreach ($b in $ish.items) {
    $nom = [string]$b.name
    $son = [string]$b.num
    if (($nom.Length + 1 + $son.Length) -le $KENG_KATTA) {
      $q += $nom + (" " * ($KENG_KATTA - $nom.Length - $son.Length)) + $son
    } else {
      $qator = ""
      foreach ($w in ($nom -split ' ')) {
        if ($w -eq "") { continue }
        if ($qator -eq "") {
          $qator = $w
        } elseif (($qator.Length + 1 + $w.Length) -le $KENG_KATTA) {
          $qator = $qator + " " + $w
        } else {
          $q += $qator
          $qator = $w
        }
        # bitta so'zning o'zi juda uzun bo'lsa -- bo'lib yuboramiz
        while ($qator.Length -gt $KENG_KATTA) {
          $q += $qator.Substring(0, $KENG_KATTA)
          $qator = $qator.Substring($KENG_KATTA)
        }
      }
      if ($qator -ne "") { $q += $qator }
      $q += (" " * ($KENG_KATTA - $son.Length)) + $son
    }
  }  $q += $chiziq
  $q += "Jami: {0} band" -f @($ish.items).Count
  $q += "Chiqarildi: " + (Get-Date -Format "dd.MM.yyyy HH:mm")
  return $q
}

function ChekMatni($ish) {
  $q = ChekQatorlar $ish
  $s = $INIT + $CP866
  # Sarlavha -- eng katta
  $s += $MARKAZ + $QALIN_ON + $KATTA + $q[0] + "`n"
  $s += $q[1] + "`n" + $QALIN_OFF + $ODDIY + $CHAP
  # Ma'lumot qatorlari (Kimga/Yozgan/Sana) -- baland, 48 belgi
  $s += $BALAND
  for ($i = 2; $i -lt 7; $i++) { $s += $q[$i] + "`n" }
  # Mahsulotlar -- ENG KATTA (2x en + 2x boy)
  $s += $KATTA + $QALIN_ON
  for ($i = 7; $i -lt $q.Count - 3; $i++) { $s += $q[$i] + "`n" }
  $s += $QALIN_OFF
  $s += $BALAND + $q[$q.Count - 3] + "`n"
  $s += $QALIN_ON + $q[$q.Count - 2] + "`n" + $QALIN_OFF
  $s += $ODDIY + $q[$q.Count - 1] + "`n"
  $s += "`n`n`n" + $KES
  return $s
}

function PrinterTop {
  $hammasi = @(Get-WmiObject -Class Win32_Printer -ErrorAction SilentlyContinue)
  if ($hammasi.Count -eq 0) { return $null }
  # 1) Buyruqda berilgan nom
  if (-not [string]::IsNullOrWhiteSpace($PrinterName)) {
    $t = @($hammasi | Where-Object { $_.Name -eq $PrinterName })
    if ($t.Count -gt 0) { return $t[0].Name }
    $t = @($hammasi | Where-Object { $_.Name -like "*$PrinterName*" })
    if ($t.Count -gt 0) { return $t[0].Name }
    return $null
  }
  # 2) Kutilgan chek printeri (2026-11-18: ANIQ nom birinchi o'rinda)
  $t = @($hammasi | Where-Object { $_.Name -eq $KUTILGAN_PRINTER })
  if ($t.Count -gt 0) { return $t[0].Name }
  # 3) Termal printerga o'xshash nom
  $t = @($hammasi | Where-Object { $_.Name -match "XP-|Xprinter|POS|Thermal|Receipt|58|80mm" })
  if ($t.Count -gt 0) { return $t[0].Name }
  # 4) Oxirgi chora -- standart printer. DIQQAT: bu lazernik bo'lishi mumkin,
  #    shuning uchun yuqorida ogohlantirish beriladi.
  $t = @($hammasi | Where-Object { $_.Default -eq $true })
  if ($t.Count -gt 0) { return $t[0].Name }
  return $hammasi[0].Name
}

# Printer chekni qabul qila oladimi. Bo'sh qaytsa -- hammasi joyida.
function PrinterMuammo($nom) {
  $p = @(Get-WmiObject -Class Win32_Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $nom })
  if ($p.Count -eq 0) { return "printer ro'yxatdan yo'qoldi" }
  if ($p[0].WorkOffline) { return "printer OFFLINE holatda" }
  switch ([int]$p[0].DetectedErrorState) {
    4  { return "QOG'OZ TUGAGAN" }
    7  { return "QOPQOQ OCHIQ" }
    8  { return "qog'oz tiqilib qolgan" }
    9  { return "printer ULANMAGAN (offline)" }
    10 { return "printer xizmat talab qilyapti" }
  }
  return ""
}

# Yuborilgan ish spoolerdan chiqib ketdimi. Bo'sh qaytsa -- muammo yo'q.
# Chek hali chop etilayotgan bo'lsa ham muvaffaqiyat deb hisoblanadi --
# aks holda uzun cheklar ikki marta chiqib ketardi.
function SpoolMuammo($nom, $soniya) {
  $oxir = (Get-Date).AddSeconds($soniya)
  while ((Get-Date) -lt $oxir) {
    $ishlar = @(Get-WmiObject -Class Win32_PrintJob -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like ($nom + ",*") })
    if ($ishlar.Count -eq 0) { return "" }
    foreach ($i in $ishlar) {
      if ([string]$i.JobStatus -match "Error|Offline|Paused|Deleting") {
        return ("spoolerda qoldi: " + [string]$i.JobStatus)
      }
    }
    Start-Sleep -Milliseconds 400
  }
  return ""
}

if ($ListPrinters) {
  Write-Host "O'rnatilgan printerlar:"
  Get-WmiObject -Class Win32_Printer -ErrorAction SilentlyContinue | ForEach-Object {
    $bel = if ($_.Default) { "[standart]" } else { "          " }
    Write-Host ("   {0} {1}    port: {2}    offline: {3}    xato-holat: {4}" -f `
      $bel, $_.Name, $_.PortName, $_.WorkOffline, $_.DetectedErrorState)
  }
  Write-Host ""
  Write-Host ("Avtomatik tanlanadigan printer: " + (PrinterTop))
  exit 0
}

if ($Test) {
  $namuna = [pscustomobject]@{
    source = "MANGAL"; dest = "OLIMP 1: Mangal sklad"; login = "Hosil"; when = "08.10.2026"
    items  = @(
      [pscustomobject]@{ name = "Ижжон шашлик (шт)  П/ф";      num = 200 },
      [pscustomobject]@{ name = "Шашлик ижжон (кг) п/ф";       num = 6.7 },
      [pscustomobject]@{ name = "Крылиишки маринад (кг) п\ф";  num = 17.2 },
      [pscustomobject]@{ name = "Гиждувон 100гр (шт) п/ф";     num = 60 }
    )
  }
  Write-Host ("=" * 34)
  foreach ($qator in (ChekQatorlar $namuna)) { Write-Host ("|" + $qator.PadRight($KENGLIK) + "|") }
  Write-Host ("=" * 34)
  Write-Host ""
  $p = PrinterTop
  Write-Host ("Topilgan printer: " + $p)
  if ($p) { Write-Host ("Printer holati  : " + $(if ((PrinterMuammo $p) -eq "") { "joyida" } else { (PrinterMuammo $p) })) }
  exit 0
}

if ([string]::IsNullOrWhiteSpace($Key)) {
  Write-Host "XATO: kalit berilmagan." -ForegroundColor Red
  exit 1
}

$PRINTER = PrinterTop
if (-not $PRINTER) {
  Yoz "XATO: bu kompyuterda birorta printer topilmadi."
  exit 1
}
Yoz "=== Chek agenti v2 (ochiq liniya) ishga tushdi. Printer: $PRINTER ==="
if ($PRINTER -match $LAZERNIK) {
  Yoz "!!! OGOHLANTIRISH: '$PRINTER' chek printeriga o'xshamaydi (lazernik/virtual)."
  Yoz "!!! Chek noto'g'ri printerga ketishi mumkin. To'g'rilash uchun agentni"
  Yoz "!!! shunday ishga tushiring:  -PrinterName `"$KUTILGAN_PRINTER`""
}

$bugungiSana = (Get-Date).ToString("yyyy-MM-dd")
$bugungiSon  = 0
$oxirgiChek  = ""

# Ekrandagi ko'rsatkich uchun holat. Har aylanishda yoziladi -- fayl
# yangilanmay qolsa ko'rsatkich "ISHLAMAYAPTI" deb qizarib qoladi.
function HolatYoz($holat) {
  try {
    $s = ("vaqt=" + [DateTimeOffset]::Now.ToUnixTimeMilliseconds()),
         ("printer=" + $PRINTER),
         ("holat=" + $holat),
         ("bugun=" + $bugungiSon),
         ("oxirgi=" + $oxirgiChek)
    Set-Content -Path $HOLAT_FAYL -Value ($s -join "`r`n") -Encoding UTF8
  } catch { }
}

HolatYoz "ishga tushdi"

$bajarildi = @()
$oxirgiTirik = Get-Date
while ($true) {
  # Kun almashsa bugungi hisob noldan boshlanadi
  $hozirSana = (Get-Date).ToString("yyyy-MM-dd")
  if ($hozirSana -ne $bugungiSana) { $bugungiSana = $hozirSana; $bugungiSon = 0 }
  $holatMatni = "ishlayapti"
  try {
    # `wait` -- bulut chekni 12 soniyagacha kutib tursin (ochiq liniya).
    $sorov = @{ key = $Key; wait = $true }
    if ($bajarildi.Count -gt 0) { $sorov.done = $bajarildi }
    $tana = $sorov | ConvertTo-Json -Compress
    $baytlar = [System.Text.Encoding]::UTF8.GetBytes($tana)
    # 2026-10-08: javob MAJBURIY UTF-8 deb o'qiladi. Invoke-RestMethod
    # (PowerShell 5.1) charset ko'rsatilmasa ISO-8859-1 deb o'qib, kirill
    # harflarni buzadi -- chekda "???" bo'lib chiqqandi.
    $javobRaw = Invoke-WebRequest -Uri $ENDPOINT -Method Post -ContentType "application/json; charset=utf-8" -Body $baytlar -TimeoutSec $TIMEOUT -UseBasicParsing
    $matnJson = [System.Text.Encoding]::UTF8.GetString($javobRaw.RawContentStream.ToArray())
    $javob = $matnJson | ConvertFrom-Json
    $bajarildi = @()

    if (-not $javob.ok) {
      Yoz ("XATO (bulut): " + [string]$javob.error)
      $holatMatni = "bulut rad etdi"
    } elseif ($javob.jobs) {
      foreach ($ish in $javob.jobs) {
        # 1) Printer chekni qabul qila oladimi
        $muammo = PrinterMuammo $PRINTER
        if ($muammo -ne "") {
          Yoz ("CHEK KUTYAPTI -- " + $muammo + "  (" + [string]$ish.source + " -> " + [string]$ish.dest + ")")
          $holatMatni = $muammo
          break    # chek navbatda qoladi, printer tuzalganda chiqadi
        }
        # 2) Yuborish
        $matn = ChekMatni $ish
        $data = [System.Text.Encoding]::GetEncoding(866).GetBytes($matn)
        $xato = [RawPrint]::Send($PRINTER, $data)
        if ($xato -ne "") {
          Yoz ("XATO (printer): " + $xato)
          $holatMatni = "printer xatosi"
          break
        }
        # 3) Rostdan chiqdimi -- spooler navbatini kuzatamiz
        $qoldi = SpoolMuammo $PRINTER 8
        if ($qoldi -ne "") {
          Yoz ("CHEK CHIQMADI -- " + $qoldi + "  (navbatda qoldi, qayta urinamiz)")
          $holatMatni = "chek spoolerda qoldi"
          break
        }
        $bajarildi += $ish.id
        $bugungiSon++
        $oxirgiChek = (Get-Date -Format "HH:mm") + " " + [string]$ish.source
        Yoz ("CHEK CHIQDI  {0} -> {1}  ({2} band)" -f $ish.source, $ish.dest, @($ish.items).Count)
      }
    }
    # Soatiga bir marta "tirikman" deb yozadi -- agent to'xtab qolganini
    # logdan bilish uchun (2026-11-18: agent jimgina to'xtab qolgan edi).
    if (((Get-Date) - $oxirgiTirik).TotalMinutes -ge 60) {
      $oxirgiTirik = Get-Date
      Yoz ("-- tirik, printer: " + $PRINTER)
    }
  } catch {
    Yoz ("XATO (internet): " + $_.Exception.Message)
    $holatMatni = "internet yo'q"
    Start-Sleep -Seconds 3
  }
  HolatYoz $holatMatni
  Start-Sleep -Seconds $INTERVAL
}
