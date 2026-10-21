import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xl;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const StockApp()); }
class StockApp extends StatelessWidget {
  const StockApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(debugShowCheckedModeBanner:false,title:'SS OIL Stok Kontrol',theme:ThemeData(colorSchemeSeed:Colors.indigo,useMaterial3:true),home:const Home());
}
class Product {
  final String code,name,barcode,price,stock;
  const Product(this.code,this.name,this.barcode,this.price,this.stock);
  Map<String,dynamic> toJson()=>{'code':code,'name':name,'barcode':barcode,'price':price,'stock':stock};
  factory Product.fromJson(Map<String,dynamic> j)=>Product('${j['code']??''}','${j['name']??''}','${j['barcode']??''}','${j['price']??''}','${j['stock']??''}');
}
class Home extends StatefulWidget { const Home({super.key}); @override State<Home> createState()=>_HomeState(); }
class _HomeState extends State<Home> with WidgetsBindingObserver {
  String? _lastProcessedPopis;
  bool _readingPopis = false;
  // Catalog keys are Artikal IDs, not barcodes. The catalog survives count resets.
  final Map<String,Product> catalog={};
  final Map<String,Map<String,dynamic>> issues={};
  final Map<String,Product> orders={};
  Product? current;
  static const bridge=MethodChannel("ssoil.popis/bridge");
  Future<void> _checkPopis({bool silent = false}) async {
    if (_readingPopis) return;
    _readingPopis = true;
    try {
      final raw=await bridge.invokeMethod<String>("readPopis");
      if(raw==null||raw.isEmpty){if(!silent)_msg("Popis ekranından henüz veri alınmadı");return;}
      if (raw == _lastProcessedPopis) {if(!silent)_msg("Cadmus verisi zaten işlendi");return;}
      final p=_parsePopis(raw);
      if(p==null){if(!silent)_msg('Popis metninde ID, isim, fiyat veya stok bulunamadı');return;}
      final accepted = await _acceptPopis(p);
      if (accepted) _lastProcessedPopis = raw;
    }catch(e){if(!silent)_msg("Popis erişimi: $e");}
    finally {_readingPopis = false;}
  }
  // Popis accessibility snapshots are plain text separated by |, not JSON.
  // Accept Cyrillic/Latin field labels and multiline product names.
  Product? _parsePopis(String raw) {
    final parts = raw.split(RegExp(r'\s*\|\s*|\r?\n'))
        .map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
    String? field(List<String> labels) {
      for (var i = 0; i < parts.length; i++) {
        final part = parts[i];
        for (final label in labels) {
          final pattern = RegExp('^${RegExp.escape(label)}\\s*[:：]?\\s*(.*)\$', caseSensitive: false);
          final match = pattern.firstMatch(part);
          if (match == null) continue;
          var value = (match.group(1) ?? '').trim();
          if (value == ':' || value == '：') value = '';
          if (value.isNotEmpty) return value;
          for (var j = i + 1; j < parts.length && j <= i + 2; j++) {
            final candidate = parts[j].replaceFirst(RegExp(r'^[:：]\s*'), '').trim();
            if (candidate.isNotEmpty) return candidate;
          }
        }
      }
      return null;
    }
    final id = field(['Artikal ID']);
    final name = field(['Име', 'Ime']);
    final price = field(['Цијена', 'Cijena', 'Цена']);
    final stock = field(['Количина', 'Količina', 'Kolicina']);
    if (id == null || !RegExp(r'^\d+$').hasMatch(id) ||
        name == null || name.isEmpty || price == null || stock == null) return null;
    final number = RegExp(r'-?\d+(?:[.,]\d+)?');
    final p = number.firstMatch(price)?.group(0);
    final q = number.firstMatch(stock)?.group(0);
    if (p == null || q == null) return null;
    return Product(id, name, '', p.replaceAll(',', '.'), q.replaceAll(',', '.'));
  }
  Future<void> _startPopisScan() async {
    // Keep the existing Home state alive while Cadmus is in the foreground.
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => PopisTransferPage(
        openCadmus: () async {
          _lastProcessedPopis = null;
          await bridge.invokeMethod<void>('armPopis');
        },
        complete: () async {
          // A failed or cancelled scan must not clear the existing stocktake.
          await _checkPopis();
        },
      )),
    );
  }
  Future<void> _openAccess() async {try{await bridge.invokeMethod("accessibilitySettings");}catch(e){_msg("Ayarlar açılamadı: $e");}}
  Future<void> _returnPopis() async {try{await bridge.invokeMethod("returnPopis");}catch(e){_msg("Popis dönüşü başarısız: $e");}}
  final count=TextEditingController();
  final search=TextEditingController();
  String status='Ürün listesi yükleyin veya barkod okutun';
  @override void initState(){
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Cadmus was in foreground: process the latest captured product on return.
      unawaited(_checkPopis(silent: true));
    }
  }
  @override void dispose(){
    WidgetsBinding.instance.removeObserver(this);
    count.dispose();search.dispose();super.dispose();
  }
  Future<void> _load() async {
    final p=await SharedPreferences.getInstance();
    try {
      final c=jsonDecode(p.getString('catalog')??'[]') as List;
      final i=jsonDecode(p.getString('issues')??'[]') as List;
      final o=jsonDecode(p.getString('orders')??'[]') as List;
      setState((){
        for(final x in c){final a=Product.fromJson(Map<String,dynamic>.from(x));if(a.code.isNotEmpty)catalog[a.code]=a;}
        for(final x in i){final m=Map<String,dynamic>.from(x);issues['${m['code']}']=m;}
        for(final x in o){final a=Product.fromJson(Map<String,dynamic>.from(x));orders[a.code]=a;}
      });
    } catch(_){setState(()=>status='Kayıt okuma hatası');}
  }
  Future<void> _save() async {
    final p=await SharedPreferences.getInstance();
    await p.setString('catalog',jsonEncode(catalog.values.map((x)=>x.toJson()).toList()));
    await p.setString('issues',jsonEncode(issues.values.toList()));
    await p.setString('orders',jsonEncode(orders.values.map((x)=>x.toJson()).toList()));
  }
  void _msg(String s){if(mounted){setState(()=>status=s);ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s),duration:const Duration(seconds:1)));}}
  Future<void> _scan() async {
    final code=await Navigator.push<String>(context,MaterialPageRoute(builder:(_)=>const ScanPage()));
    if(code==null)return;
    final p=catalog[code] ?? catalog.values.where((p)=>p.barcode==code).firstOrNull;
    if(p==null){_msg('Barkod listede bulunamadı: $code');return;}
    setState((){current=p;count.clear();status='Ürün bulundu';});
  }
  Future<bool> _acceptPopis(Product incoming) async {
    final old=catalog[incoming.code];
    if(old==null || old.barcode.isEmpty){
      final barcode=await _askBarcode(incoming);
      if(barcode==null || barcode.isEmpty){_msg('Yeni ürün için barkod kaydı bekleniyor');return false;}
      if(catalog.values.any((p)=>p.code!=incoming.code && p.barcode==barcode)){
        _msg('Bu barkod başka bir üründe kayıtlı');return false;
      }
      catalog[incoming.code]=Product(incoming.code,incoming.name,barcode,incoming.price,incoming.stock);
    } else {
      // Only current price and stock change. Preserve permanent identity fields.
      catalog[incoming.code]=Product(old.code,old.name,old.barcode,incoming.price,incoming.stock);
    }
    await _save();
    if(!mounted)return true;
    setState((){current=catalog[incoming.code];count.clear();status='Cadmus verisi güncellendi';});
    return true;
  }
  Future<String?> _askBarcode(Product p) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) => AlertDialog(
          title: const Text('Yeni ürün – Barkodu okutun'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Artikal ID: ${p.code}'),
              Text(p.name),
              Text('Fiyat: ${p.price} KM   Stok: ${p.stock}'),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Barkod',
                  border: OutlineInputBorder(),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  final code = await Navigator.push<String>(
                    dialogContext,
                    MaterialPageRoute(builder: (_) => const ScanPage()),
                  );
                  if (code != null) {
                    ctrl.text = code;
                    update(() {});
                  }
                },
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Kamerayla barkod tara'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, ctrl.text.trim()),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    // Dispose after the dialog route has completed its exit animation.
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    return result;
  }
  Future<void> _addManual() async {
    final id=TextEditingController(),name=TextEditingController(),barcode=TextEditingController(),price=TextEditingController(),stock=TextEditingController();
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:const Text('Manuel ürün ekle'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        for(final field in <(TextEditingController,String)>[(id,'Artikal ID'),(name,'Ürün adı'),(barcode,'Barkod'),(price,'Fiyat'),(stock,'Stok')])
          Padding(padding:const EdgeInsets.only(bottom:8),child:TextField(controller:field.$1,decoration:InputDecoration(labelText:field.$2,border:const OutlineInputBorder()))),
      ])),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Vazgeç')),
        FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Kaydet'))]));
    if(ok==true){
      final code=id.text.trim(),ean=barcode.text.trim();
      if(code.isEmpty||name.text.trim().isEmpty||ean.isEmpty){_msg('ID, isim ve barkod gerekli');}
      else if(catalog.containsKey(code)||catalog.values.any((x)=>x.barcode==ean)){_msg('Bu ID veya barkod zaten kayıtlı');}
      else {catalog[code]=Product(code,name.text.trim(),ean,price.text.trim(),stock.text.trim());await _save();setState((){current=catalog[code];});_msg('Ürün kalıcı olarak kaydedildi');}
    }
    for(final c in [id,name,barcode,price,stock]){c.dispose();}
  }
  Future<void> _editCurrent() async {
    final p=current;if(p==null)return;
    final price=TextEditingController(text:p.price),stock=TextEditingController(text:p.stock);
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text('Stok ve fiyat – ${p.code}'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:price,decoration:const InputDecoration(labelText:'Satış fiyatı')),
        TextField(controller:stock,decoration:const InputDecoration(labelText:'Stok miktarı'))]),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Vazgeç')),
        FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Kaydet'))]));
    if(ok==true){final updated=Product(p.code,p.name,p.barcode,price.text.trim(),stock.text.trim());catalog[p.code]=updated;await _save();if(mounted)setState(()=>current=updated);_msg('Fiyat ve stok güncellendi');}
    price.dispose();stock.dispose();
  }
  // Excel/CSV import is update-only. Unknown Artikal IDs are skipped.
  Future<void> _import() async {
    final r=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['xlsx','csv']);
    if(r==null||r.files.single.path==null)return;
    try {
      final file=File(r.files.single.path!);
      List<List<String>> rows=[];
      if(file.path.toLowerCase().endsWith('.xlsx')){
        final book=xl.Excel.decodeBytes(await file.readAsBytes());
        final sheet=book.tables.values.first;
        if(sheet==null)throw Exception('Excel sayfası boş');
        rows=sheet.rows.map((r)=>r.map((c)=>c?.value?.toString()??'').toList()).toList();
      } else {
        final raw=await file.readAsString();
        final delimiter=raw.split('\n').first.contains(';')?';':',';
        rows=CsvToListConverter(fieldDelimiter:delimiter,shouldParseNumbers:false).convert(raw)
          .map((r)=>r.map((x)=>x.toString()).toList()).toList();
      }
      if(rows.length<2)throw Exception('Ürün satırı bulunamadı');
      String norm(String s)=>s.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9ğüşöçıа-я]'), '');
      final h=rows.first.map(norm).toList();
      int idx(List<String> opts){for(final x in opts){final i=h.indexOf(norm(x));if(i>=0)return i;}return -1;}
      final ci=idx(['artikal id','artikalid','code','ürün kodu','urun kodu','šifra']);
      final pi=idx(['price','fiyat','cijena','prodajna cijena','satış fiyatı']);
      final si=idx(['stock','stok','stanje','količina','kolicina']);
      if(ci<0 || (pi<0&&si<0))throw Exception('Başlıklar: Artikal ID, Fiyat, Stok');
      String cell(List<String> row,int i)=>i<0||i>=row.length?'':row[i].trim();
      int changed=0,skipped=0;
      for(final row in rows.skip(1)){
        final id=cell(row,ci);final old=catalog[id];
        if(old==null){skipped++;continue;}
        final price=cell(row,pi),stock=cell(row,si);
        if(price.isEmpty&&stock.isEmpty)continue;
        catalog[id]=Product(old.code,old.name,old.barcode,price.isEmpty?old.price:price,stock.isEmpty?old.stock:stock);
        changed++;
      }
      await _save();if(current!=null && mounted){setState(()=>current=catalog[current!.code]);}
      _msg('$changed kayıt güncellendi; $skipped kayıtlı olmayan ID atlandı');
    }catch(e){_msg('Excel aktarım hatası: $e');}
  }
  void _issue(String type) {
    final p=current;if(p==null)return;
    final existing=issues[p.code]??{'code':p.code,'name':p.name,'barcode':p.barcode,'price':p.price,'stock':p.stock,'count':'','types':<String>[]};
    // Always compare against the current single stock value.
    existing['price']=p.price;
    existing['stock']=p.stock;
    final types=List<String>.from(existing['types'] as List);
    if(type=='Eksik'||type=='Fazla'){
      final q=double.tryParse(count.text.replaceAll(',','.'));
      final s=double.tryParse(p.stock.replaceAll(',','.'));
      if(q==null||q<0||s==null){_msg('Geçerli sayılan miktar ve sistem stoku gerekli');return;}
      if(type=='Eksik'&&q>=s || type=='Fazla'&&q<=s){_msg('Sayılan stok ile seçilen durum uyuşmuyor');return;}
      types.remove('Eksik');types.remove('Fazla');existing['count']=count.text;
    }
    if(type=='Sorun Yok'){types.clear();existing['count']='';}else{types.remove('Sorun Yok');}
    if(!types.contains(type))types.add(type);
    existing['types']=types;
    issues[p.code]=existing;
    unawaited(_save());_msg('$type kaydedildi / mevcut kayıt güncellendi');setState((){});
  }
  void _ok(){_issue('Sorun Yok');}
  void _order(){final p=current;if(p==null)return;orders[p.code]=p;unawaited(_save());_msg('Sipariş listesine eklendi / güncellendi');setState((){});}
  Future<void> _export() async {
    try {
      final book=xl.Excel.createExcel();
      final a=book['Stok Kontrol'],b=book['Siparis Listesi'],c=book['Urun Veritabani'],d=book['Manuel Stok'];
      void row(xl.Sheet s,List<String> vals)=>s.appendRow(vals.map((v)=>xl.TextCellValue(v)).toList());
      row(a,['Artikal ID','Ürün Adı','Barkod','Satış Fiyatı','Sistem Stoku','Sayılan Stok','Fark','Sorunlar']);
      for(final m in issues.values){
        final st=double.tryParse('${m['stock']}'.replaceAll(',','.'));
        final co=double.tryParse('${m['count']}'.replaceAll(',','.'));
        final types=List<String>.from(m['types'] as List);
        row(a,['${m['code']}','${m['name']}','${m['barcode']}','${m['price']}','${m['stock']}','${m['count']}',st!=null&&co!=null?'${co-st}':'',types.join(', ')]);
      }
      row(b,['Artikal ID','Ürün Adı','Barkod']);
      for(final p in orders.values){row(b,[p.code,p.name,p.barcode]);}
      row(c,['Artikal ID','Ürün Adı','Barkod','Fiyat','Stok']);
      row(d,['Artikal ID','Fiyat','Stok']);
      for(final p in catalog.values){row(c,[p.code,p.name,p.barcode,p.price,p.stock]);row(d,[p.code,p.price,p.stock]);}
      book.delete('Sheet1');
      final bytes=book.encode();if(bytes==null)throw Exception('Excel oluşturulamadı');
      final now=DateTime.now();
      final stamp='${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}_${now.hour}${now.minute.toString().padLeft(2,'0')}';
      final filename='SS_OIL_Stok_$stamp.xlsx';
      // Android system save dialog, not share-only. User selects destination.
      final path=await FilePicker.platform.saveFile(dialogTitle:'Excel dosyasını kaydet',fileName:filename,
        type:FileType.custom,allowedExtensions:['xlsx'],bytes:Uint8List.fromList(bytes));
      if(path==null){_msg('Kaydetme iptal edildi');return;}
      _msg('Excel kaydedildi: $path');
    }catch(e){_msg('Excel kaydetme hatası: $e');}
  }
  Future<void> _clear() async {
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Kayıtları temizle?'),content:const Text('Stok kontrol ve sipariş kayıtları silinir. Önceden dışarı aktarılan Excel dosyaları silinmez. Ürün kataloğu korunur.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Vazgeç')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Temizle'))]));
    if(ok!=true)return;setState((){issues.clear();orders.clear();current=null;count.clear();});await _save();_msg('Yeni kontrol dönemi başladı');
  }
  Future<void> _lists() async {await Navigator.push(context,MaterialPageRoute(builder:(_)=>ListPage(issues:issues,orders:orders,onChanged:() async {await _save();setState((){});})));setState((){});}
  @override Widget build(BuildContext context){final p=current;return Scaffold(appBar:AppBar(title:const Text('SS OIL • Stok Kontrol')),body:ListView(padding:const EdgeInsets.all(16),children:[
    Wrap(spacing:8,runSpacing:8,children:[OutlinedButton.icon(onPressed:_openAccess,icon:const Icon(Icons.accessibility_new),label:const Text('Erişilebilirlik Ayarı')),OutlinedButton.icon(onPressed:_startPopisScan,icon:const Icon(Icons.sync),label:const Text('Popis Veri Al')),FilledButton.icon(onPressed:_scan,icon:const Icon(Icons.qr_code_scanner),label:const Text('Barkod Oku')),OutlinedButton.icon(onPressed:_import,icon:const Icon(Icons.file_open),label:const Text('Excel’den Güncelle')),OutlinedButton.icon(onPressed:_addManual,icon:const Icon(Icons.add),label:const Text('Manuel Ürün Ekle')),OutlinedButton.icon(onPressed:_lists,icon:const Icon(Icons.list),label:Text('Listeler (${issues.length} / ${orders.length})'))]),
    const SizedBox(height:12),Text(status,style:Theme.of(context).textTheme.bodySmall),const SizedBox(height:12),
    TextField(controller:search,decoration:InputDecoration(labelText:'Barkod veya ürün kodunu elle gir',suffixIcon:IconButton(icon:const Icon(Icons.search),onPressed:(){final v=search.text.trim();final match=catalog[v]??catalog.values.where((x)=>x.barcode==v).firstOrNull;if(match==null){_msg('Ürün bulunamadı');return;}setState((){current=match;count.clear();});})),onSubmitted:(v){final match=catalog[v.trim()]??catalog.values.where((x)=>x.barcode==v.trim()).firstOrNull;if(match!=null)setState((){current=match;count.clear();});else _msg('Ürün bulunamadı');}),
    const SizedBox(height:12),if(p!=null)...[
      Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Kod: ${p.code}'),Text(p.name,style:Theme.of(context).textTheme.titleMedium),Text('Barkod: ${p.barcode}'),Text('Satış: ${p.price} KM     Stok: ${p.stock}',style:Theme.of(context).textTheme.titleSmall),TextButton.icon(onPressed:_editCurrent,icon:const Icon(Icons.edit),label:const Text('Fiyat / Stok Düzenle'))]))),
      const SizedBox(height:12),TextField(controller:count,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(border:OutlineInputBorder(),labelText:'Gerçek sayılan stok')),
      const SizedBox(height:8),Row(children:[Expanded(child:FilledButton.tonal(onPressed:()=>_issue('Eksik'),child:const Text('Eksik'))),const SizedBox(width:8),Expanded(child:FilledButton.tonal(onPressed:()=>_issue('Fazla'),child:const Text('Fazla')))]),
      for(final label in ['Yanlış Barkod','Yanlış Fiyat','Etiket Yok']) Padding(padding:const EdgeInsets.only(top:8),child:OutlinedButton(onPressed:()=>_issue(label),child:Text(label))),
      const SizedBox(height:10),OutlinedButton(onPressed:_ok,child:const Text('Sorun Yok – Kaydet')),FilledButton.icon(onPressed:_order,icon:const Icon(Icons.shopping_cart),label:const Text('Sipariş Listesine Ekle')),
    ]else const Card(child:Padding(padding:EdgeInsets.all(20),child:Text('Ürün seçmek için barkod okutun veya ürün kodunu girin.'))),
    const SizedBox(height:8),OutlinedButton(onPressed:()=>_checkPopis(),child:const Text('Yakalanan Popis Verisini Oku')),const Divider(height:32),FilledButton.icon(onPressed:_export,icon:const Icon(Icons.table_view),label:const Text('Excel’e Kaydet (4 Sayfa)')),
    const SizedBox(height:8),OutlinedButton.icon(onPressed:_clear,icon:const Icon(Icons.delete_outline),label:const Text('Önceki Kayıtları Temizle')),
  ]));}
}
/// Dedicated transfer screen. Cadmus itself runs as a separate full-screen app.
/// Returning to SS OIL does not discard the existing Home/count state.
class PopisTransferPage extends StatefulWidget {
  final Future<void> Function() openCadmus;
  final Future<void> Function() complete;
  const PopisTransferPage({super.key, required this.openCadmus, required this.complete});
  @override State<PopisTransferPage> createState() => _PopisTransferPageState();
}

class _PopisTransferPageState extends State<PopisTransferPage> {
  bool busy = false;
  String message = 'Cadmus’u açıp ürünü taratın.';

  Future<void> _open() async {
    if (busy) return;
    setState(() { busy = true; message = 'Cadmus açılıyor…'; });
    try {
      await widget.openCadmus();
      if (mounted) setState(() => message = 'Cadmus’tan döndüğünüzde Tamam’a basın.');
    } catch (e) {
      if (mounted) setState(() => message = 'Cadmus açılamadı: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _complete() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      // Pop the transfer page first so barcode registration dialogs belong to Home.
      if (mounted) Navigator.of(context).pop();
      await widget.complete();
    } catch (_) {
      // Home reports bridge/read errors via its existing status/snackbar.
    }
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Popis Veri Al')),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Cadmus tam ekran açılır. Barkodu okutun. Artikal ID görünürse ürün bilgileri yakalanır.'),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: busy ? null : _open,
          icon: const Icon(Icons.open_in_new),
          label: const Text('Cadmus’u Aç'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: busy ? null : _complete,
          icon: const Icon(Icons.check),
          label: const Text('Tamam – SS OIL’e Dön'),
        ),
        const SizedBox(height: 14),
        Text(message),
        const SizedBox(height: 8),
        const Text('Android otomatik geri dönüşü engellerse son uygulamalardan SS OIL’e dönün ve Tamam’a basın.'),
      ]),
    ),
  );
}

class ScanPage extends StatefulWidget {const ScanPage({super.key});@override State<ScanPage> createState()=>_ScanPageState();}
class _ScanPageState extends State<ScanPage>{bool done=false;@override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Barkod Tara')),body:MobileScanner(onDetect:(capture){if(done)return;final code=capture.barcodes.firstOrNull?.rawValue;if(code==null||code.isEmpty)return;done=true;Navigator.pop(context,code);}));}
class ListPage extends StatefulWidget {final Map<String,Map<String,dynamic>> issues;final Map<String,Product> orders;final Future<void> Function() onChanged;const ListPage({super.key,required this.issues,required this.orders,required this.onChanged});@override State<ListPage> createState()=>_ListPageState();}
class _ListPageState extends State<ListPage>{@override Widget build(BuildContext context)=>DefaultTabController(length:2,child:Scaffold(appBar:AppBar(title:const Text('Kayıt Listeleri'),bottom:const TabBar(tabs:[Tab(text:'Stok / Hatalar'),Tab(text:'Sipariş')])),body:TabBarView(children:[ListView(children:widget.issues.entries.map((e)=>ListTile(title:Text('${e.value['name']}'),subtitle:Text('Kod: ${e.key} • ${e.value['types'].join(', ')} • Sayılan: ${e.value['count']}'),trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()async{setState(()=>widget.issues.remove(e.key));await widget.onChanged();}))).toList()),ListView(children:widget.orders.entries.map((e)=>ListTile(title:Text(e.value.name),subtitle:Text('Kod: ${e.value.code} • Barkod: ${e.value.barcode}'),trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()async{setState(()=>widget.orders.remove(e.key));await widget.onChanged();}))).toList())])));}
