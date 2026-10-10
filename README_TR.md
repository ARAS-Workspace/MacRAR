<p align="center">
  <img src="https://raw.githubusercontent.com/ARAS-Workspace/MacRAR/press-kit/assets/macrar-app-icon.png" width="128" alt="MacRAR simgesi">
</p>

<p align="center">
  <a href="README.md">🇺🇸</a>&nbsp;&nbsp;<a href="README_TR.md">🇹🇷</a>
</p>

<h1 align="center">MacRAR</h1>

<p align="center">
  macOS için WinRAR tarzı arşiv yöneticisi. Arşivleri uygulamanın içine gömülü 7-Zip ile açar, çıkartır ve oluşturur.<br>
  Yerel AppKit arayüzü · Finder sağ tık Hızlı Eylemleri · şifreli arşivler · çok parçalı arşivler · 30+ biçim
</p>

---

Mesut Çevik'in [MacRAR](https://github.com/mstcvk/MacRAR) projesi üzerine ARAS-Workspace tarafından hazırlanan bağımsız dağıtım.

7-Zip uygulamaya bir FFI katmanıyla kütüphane olarak gömülüdür. Arşivleri açmak, çıkartmak ve oluşturmak için ayrıca bir araç indirmeniz, kurmanız ya da uygulamayı kendiniz derleyip imzalamanız gerekmez. Sürümler Developer ID ile imzalanmış ve Apple tarafından notarize edilmiş olarak gelir. Güncelleme denetimi bu deponun sürümlerini izler.

Sürüm numarası, dayandığı özgün sürümü ve bu dağıtımın yama turunu birlikte taşır: `<özgün sürüm>+ARAS.Patch.<n>`. Güncel sürüm ve her turda nelerin değiştiği [CHANGELOG](CHANGELOG) dosyasındadır.

## Gereksinimler

- macOS 13 (Ventura) veya üzeri, Apple Silicon ya da Intel
- RAR arşivi oluşturmak için RARLAB'ın `rar` aracı (aşağıdaki ipucuna bakın); RAR açmak ve çıkartmak için gerekmez

## Kurulum

| Mimari                      | Dosya                       |
|-----------------------------|-----------------------------|
| Apple Silicon (M1/M2/M3/M4) | `MacRAR-<sürüm>-arm64.dmg`  |
| Intel                       | `MacRAR-<sürüm>-x86_64.dmg` |

1. [Releases](https://github.com/ARAS-Workspace/MacRAR/releases/latest) sayfasından mimarinize uygun DMG dosyasını indirin
2. **MacRAR** uygulamasını **Applications** klasörüne sürükleyin
3. Bir kez açın; Finder Hızlı Eylemleri ilk açılışta kurulur ve hangi arşiv türlerinin MacRAR ile açılacağı sorulur

> [!TIP]
> RAR arşivlerini açmak, çıkartmak ve test etmek için başka bir şey gerekmez; bunu uygulamadaki 7-Zip yapar. RAR arşivi oluşturmak ya da bir RAR arşivini değiştirmek içinse RARLAB'ın ücretli "RAR for macOS" aracı gerekir (40 günlük deneme sürümü vardır). Lisansı izin vermediği için MacRAR bu aracı içinde taşımaz ve kendisi indirmez.
>
> [rarlab.com](https://www.rarlab.com/download.htm) adresinden Apple Silicon için "RAR for macOS ARM", Intel için "RAR for macOS x64" sürümünü indirin ve *Ayarlar… → RAR aracı → RAR Aracını Kur…* ile indirdiğiniz dosyayı gösterin. `/usr/local/bin/rar` ya da `/opt/homebrew/bin/rar` konumundaki bir `rar` kendiliğinden bulunur.

## Komut satırı modları

Finder Hızlı Eylemleri uygulamayı şöyle çağırır:

```bash
open -n -a /Applications/MacRAR.app --args --extract-here /yol/arsiv.rar
```

| Bayrak                    | Finder'daki karşılığı   | Etkisi                                                           |
|---------------------------|-------------------------|------------------------------------------------------------------|
| `--extract-here`          | MacRAR: Buraya Çıkart   | Arşivin yanına çıkartır                                          |
| `--extract-folder`        | MacRAR: Klasöre Çıkart  | Arşivin adını taşıyan bir klasöre çıkartır                       |
| `--extract-to`            | MacRAR • Şuraya Çıkart… | Hedef klasörü bir kez sorar, sonra çıkartır                      |
| `--test`                  | MacRAR • Test Et        | Arşivi test eder ve sonucu bildirir                              |
| `--compress`              | MacRAR • Hızlı Sıkıştır | Pencere açmadan, Ayarlar'daki varsayılan biçimle arşiv oluşturur |
| `--compress-dialog`       | MacRAR ile Sıkıştır…    | Arşiv Oluştur penceresini açar                                   |
| `--set-default`           | —                       | MacRAR'ı `.rar` dosyaları için varsayılan uygulama yapar         |
| `--install-quick-actions` | —                       | Finder Hızlı Eylemlerini (yeniden) kurar                         |

Bayraktan sonra birden çok dosya verilebilir. Çok parçalı arşivlerin (`.part1.rar`, `.7z.001` …) tüm parçaları verilse bile set bir kez, ilk parçadan başlayarak işlenir.

## Üçüncü taraf yazılımlar

- **7-Zip** © Igor Pavlov. GNU LGPL 2.1 veya sonrası; RAR çözücü dosyaları unRAR kısıtlamasıyla, bazı dosyalar BSD 3-clause, BSD 2-clause ya da kamu malı. Uygulamaya [ARAS-Workspace/7zip](https://github.com/ARAS-Workspace/7zip) fork'unda derlenen statik bir kütüphane olarak bağlıdır; kütüphanenin kaynak kodu ve derleme betikleri orada yayımlanır, lisans metni uygulama paketinde `7zip-license.txt` olarak bulunur. Ayrıntılar [Libraries/SevenZipKit/NOTICE](Libraries/SevenZipKit/NOTICE) dosyasında. Bkz. [7-zip.org](https://www.7-zip.org).
- **RAR / UNRAR** © Alexander Roshal, RARLAB. MacRAR RARLAB'ın araçlarını içermez: RAR arşivleri 7-Zip'in unRAR koduyla okunur, RAR oluşturmak için kullanıcının kurduğu `rar` çalıştırılır. Bkz. [rarlab.com](https://www.rarlab.com).

Bu projelerin hiçbiri MacRAR ile bağlantılı değildir. "WinRAR" ve "RAR" sahibinin ticari markalarıdır.

## Geliştirici

**Mesut Çevik** · [github.com/mstcvk](https://github.com/mstcvk)

Bağımsız dağıtım: [ARAS-Workspace](https://github.com/ARAS-Workspace)

## Lisans

MacRAR kaynak kodu [MIT Lisansı](LICENSE) ile yayımlanmıştır.
