# SS OIL - Kontrol ve test notları

- Cadmus uygulama paketi: `com.mladost.cadmus`.
- `Popis Verisini Dene` önce yakalamayı etkinleştirir, sonra Cadmus'u öne getirir.
- Erişilebilirlik servisi yalnızca Cadmus'tan gelen olaylara bakar ve `Artikal ID` gördüğünde 350 ms sonra ekran metnini yakalar.
- Veriyi `popis_bridge/raw_text` içine kaydeder; otomatik dönüş için SS OIL etkinliğini başlatmayı dener.
- Android/Samsung arka plandan uygulama açılmasını engelleyebilir; bu nedenle otomatik dönüş cihazda doğrulanmalıdır.
- Flutter yeniden açıldığında son metni okur. Artikal ID, isim, fiyat ve stok okunamazsa ürün kaydını değiştirmez.
- Kayıtlı ürünün yalnızca fiyatı ve tek güncel stok alanı yenilenir. Yeni ürün barkod kaydı ister.
- Excel aktarımı kayıtlı olmayan ürünleri atlar.
- GitHub Actions iş akışı Android iskeletini oluşturur ve APK derlemeyi dener.

## Yapılan statik kontroller
- ZIP dosyaları açılabilirlik testi
- Kotlin/Dart parantez sayımı
- Android manifesti XML doğrulaması
- YAML sözdizimi kontrolü (PyYAML mevcutsa)
- Kaynak kodda hedef akışın mevcut olduğunun kontrolü

## Henüz doğrulanmayanlar
- Flutter `analyze` / APK derlemesi (Flutter SDK bu ortamda kurulu değil)
- Samsung cihazda Cadmus erişilebilirlik ağacı ve otomatik öne getirme
- Cadmus gerçek verileriyle uçtan uca test

**Önemli:** Bu paket doğrulanmış APK değildir; kaynak kod paketidir.
