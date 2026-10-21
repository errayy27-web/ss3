# SS OIL Cadmus Tamam akışı

- Ana ekrana `Popis Veri Al` düğmesi: ayrı bir transfer sayfası açar.
- `Cadmus’u Aç`: mevcut `armPopis` köprüsüyle Cadmus’u tam ekranda açar.
- Cadmus penceresinde `Artikal ID` görülünce mevcut erişilebilirlik servisi veriyi kaydeder.
- Android izin verirse SS OIL kendiliğinden öne gelir; aksi hâlde son uygulamalardan geri dönülür.
- `Tamam – SS OIL’e Dön`: transfer sayfasını kapatır ve mevcut `readPopis` ile veriyi işler.
- Sayım, katalog, Excel ve diğer işlevlerin mevcut kodu değiştirilmedi.

## Sınırlar
- Bu paket kaynak kodudur; cihaz üzerinde otomatik dönüş garanti değildir.
- Flutter SDK mevcut olmadığından gerçek derleme/analyze testi bu ortamda yapılamadı.
- ZIP, XML, temel dosya bütünlüğü ve Dart blok dengesi kontrol edilir.
