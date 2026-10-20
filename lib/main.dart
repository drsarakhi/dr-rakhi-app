import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('patients');
  runApp(const DrRakhiApp());
}

class Patient {
  String name, mobile, age, type, apDate, bkashNo, bkashTx, note;
  bool isBlocked, isTrashed, okReplied;
  String comment, blockReason;
  int sl;
  Patient({this.sl=0, this.name='', this.mobile='', this.age='', this.type='', this.apDate='', this.bkashNo='', this.bkashTx='', this.note='', this.isBlocked=false, this.isTrashed=false, this.okReplied=false, this.comment='', this.blockReason=''});
}

class DrRakhiApp extends StatelessWidget {
  const DrRakhiApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'Dr.S.Rakhi', theme: ThemeData(primarySwatch: Colors.deepPurple, useMaterial3: true), home: const HomePage());
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Patient> allPatients = [];
  List<Patient> filtered = [];
  String search = '';
  String filterType = 'All';
  String filterApDate = '';
  final box = Hive.box('patients');

  @override
  void initState() { super.initState(); loadPatients(); }

  void loadPatients() {
    final data = box.values.toList();
    allPatients = data.map((e) {
      final m = Map<String, dynamic>.from(e);
      return Patient(sl: m['sl']??0, name: m['name']??'', mobile: m['mobile']??'', age: m['age']??'', type: m['type']??'', apDate: m['apDate']??'', bkashNo: m['bkashNo']??'', bkashTx: m['bkashTx']??'', note: m['note']??'', isBlocked: m['isBlocked']??false, isTrashed: m['isTrashed']??false, okReplied: m['okReplied']??false, comment: m['comment']??'', blockReason: m['blockReason']??'');
    }).toList();
    applyFilter();
  }

  void saveAll() {
    box.clear();
    for (var p in allPatients) {
      box.add({'sl': p.sl, 'name': p.name, 'mobile': p.mobile, 'age': p.age, 'type': p.type, 'apDate': p.apDate, 'bkashNo': p.bkashNo, 'bkashTx': p.bkashTx, 'note': p.note, 'isBlocked': p.isBlocked, 'isTrashed': p.isTrashed, 'okReplied': p.okReplied, 'comment': p.comment, 'blockReason': p.blockReason});
    }
  }

  void applyFilter() {
    setState(() {
      filtered = allPatients.where((p) {
        if (p.isTrashed) return false;
        if (filterType != 'All' && p.type != filterType) return false;
        if (filterApDate.isNotEmpty && !p.apDate.toLowerCase().contains(filterApDate.toLowerCase())) return false;
        if (search.isEmpty) return true;
        final s = search.toLowerCase();
        return p.name.toLowerCase().contains(s) || p.mobile.contains(s) || p.bkashNo.contains(s) || p.bkashTx.toLowerCase().contains(s) || p.age.contains(s);
      }).toList();
      filtered.sort((a,b)=> a.sl.compareTo(b.sl));
    });
  }

  Future<void> pickAndParse() async {
    final picker = ImagePicker();
    final result = await showModalBottomSheet<String>(context: context, builder: (c)=> SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: Icon(Icons.camera_alt), title: Text('ক্যামেরা'), onTap: ()=> Navigator.pop(c,'camera')),
      ListTile(leading: Icon(Icons.photo), title: Text('গ্যালারি থেকে ছবি'), onTap: ()=> Navigator.pop(c,'gallery')),
    ])));
    if (result==null) return;
    try {
      String? path;
      final x = await picker.pickImage(source: result=='camera'?ImageSource.camera:ImageSource.gallery, imageQuality: 90);
      path = x?.path;
      if (path==null) return;
      showDialog(context: context, barrierDismissible: false, builder: (_)=> Center(child: CircularProgressIndicator()));
      final inputImage = InputImage.fromFilePath(path);
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final recognized = await recognizer.processImage(inputImage);
      await recognizer.close();
      if (mounted) Navigator.pop(context);
      parseTableText(recognized.text);
      try { await File(path).delete(); } catch(_){}
    } catch(e) {
      if (mounted) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void parseTableText(String fullText) {
    final mobileReg = RegExp(r'01[0-9]{9}');
    List<Patient> newList = [];
    for (var rawLine in fullText.split('\n')) {
      var line = rawLine.trim();
      if (line.length < 8) continue;
      if (line.toLowerCase().contains('p. name') || line.toLowerCase().contains('all appointments')) continue;
      final mobiles = mobileReg.allMatches(line).map((m)=> m.group(0)!).toList();
      if (mobiles.isEmpty) continue;
      String mobile = mobiles.first;
      String bkashNo = mobiles.length > 1 ? mobiles.last : mobile;
      String tx = '';
      final txMatch = RegExp(r'DJ[A-Z0-9]{6,12}').firstMatch(line.toUpperCase());
      if (txMatch != null) tx = txMatch.group(0)!;
      String type = '';
      if (line.contains('New')) type='New'; else if (line.contains('Old')) type='Old';
      String name = '';
      var cleaned = line.replaceAll(RegExp(r'^\d+\s+'), '');
      var parts = cleaned.split(RegExp(r'\s{2,}'));
      if (parts.isNotEmpty) {
        var cand = parts[0].trim().replaceAll(RegExp(r'01[0-9]{9}'), '').trim();
        if (cand.length > 2 && !cand.toLowerCase().contains('october')) name = cand;
      }
      if (name.isEmpty || name.toLowerCase().contains('october')) {
        name = '';
        for (var token in cleaned.split(' ')) {
          if (token.isEmpty) continue;
          if (mobileReg.hasMatch(token)) break;
          if (token.toLowerCase().contains('old') || token.toLowerCase().contains('new')) break;
          if (RegExp(r'DJ[A-Z0-9]+').hasMatch(token.toUpperCase())) break;
          if (token.toLowerCase() == 'october') continue;
          if (RegExp(r'^[A-Za-z]').hasMatch(token)) {
            name = name.isEmpty ? token : '$name $token';
          }
          if (name.split(' ').length >= 3) break;
        }
      }
      String age = '';
      for (var m in RegExp(r'\b(1[5-9]|[2-5][0-9])\b').allMatches(line)) {
        var v = m.group(0)!;
        var iv = int.tryParse(v) ?? 0;
        if (iv >= 15 && iv <= 60) { age = v; break; }
      }
      if (name.length < 2) continue;
      if (name.toLowerCase() == 'october') continue;
      newList.add(Patient(sl: allPatients.length + newList.length + 1, name: name.trim(), mobile: mobile, age: age, type: type, apDate: '21 October 2026', bkashNo: bkashNo, bkashTx: tx));
    }
    if (newList.isEmpty) {
      showDialog(context: context, builder: (c)=> AlertDialog(title: Text('কিছু পাওয়া যায়নি'), content: SingleChildScrollView(child: Text(fullText)), actions: [TextButton(onPressed: ()=> Navigator.pop(c), child: Text('OK'))]));
      return;
    }
    showDialog(context: context, builder: (c)=> AlertDialog(
      title: Text('${newList.length} জন পাওয়া গেছে'),
      content: SizedBox(width: double.maxFinite, height: 350, child: ListView.builder(itemCount: newList.length, itemBuilder: (_,i){
        final p = newList[i];
        return Card(child: ListTile(title: Text('${p.name} - ${p.mobile}'), subtitle: Text('Age:${p.age} ${p.type} Tx:${p.bkashTx}')));
      })),
      actions: [
        TextButton(onPressed: ()=> Navigator.pop(c), child: Text('বাতিল')),
        ElevatedButton(onPressed: (){
          setState((){
            allPatients.addAll(newList);
            saveAll();
            applyFilter();
          });
          Navigator.pop(c);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${newList.length} জন যোগ করা হয়েছে')));
        }, child: Text('সব যোগ করুন'))
      ]
    ));
  }

  void shareWhatsApp() {
    if (filtered.isEmpty) return;
    bool includeName=true, includeMobile=true, includeType=true, includeAge=true;
    showDialog(context: context, builder: (c){
      return StatefulBuilder(builder: (c2,setS){
        return AlertDialog(
          title: Text('কি কি শেয়ার করবেন?'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            CheckboxListTile(value: includeName, title: Text('নাম'), onChanged: (v)=> setS(()=> includeName=v!)),
            CheckboxListTile(value: includeMobile, title: Text('মোবাইল'), onChanged: (v)=> setS(()=> includeMobile=v!)),
            CheckboxListTile(value: includeType, title: Text('Old/New'), onChanged: (v)=> setS(()=> includeType=v!)),
            CheckboxListTile(value: includeAge, title: Text('Age'), onChanged: (v)=> setS(()=> includeAge=v!)),
          ]),
          actions: [
            TextButton(onPressed: (){
              Navigator.pop(c);
              StringBuffer sb = StringBuffer();
              for (int i=0;i<filtered.length;i++) {
                final p = filtered[i];
                sb.write('${(i+1).toString().padLeft(2,'0')} ');
                if (includeName) sb.write('${p.name} ');
                if (includeMobile) sb.write('${p.mobile} ');
                if (includeType) sb.write('${p.type} ');
                if (includeAge) sb.write('${p.age}');
                sb.writeln('\n');
              }
              Share.share(sb.toString());
            }, child: Text('WhatsApp এ শেয়ার'))
          ]
        );
      });
    });
  }

  Future<void> generatePDF() async {
    final pdf = pw.Document();
    pdf.addPage(pw.MultiPage(build: (ctx)=> [
      pw.Header(text: 'Appointments'),
      pw.Table.fromTextArray(headers: ['SL','Name','Mobile','Age','Type','bKash','TX'], data: filtered.map((p)=> [p.sl.toString(), p.name, p.mobile, p.age, p.type, p.bkashNo, p.bkashTx]).toList())
    ]));
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/appointments.pdf');
    await file.writeAsBytes(await pdf.save());
    Share.shareXFiles([XFile(file.path)]);
  }

  void showPatientOptions(Patient p) {
    showModalBottomSheet(context: context, builder: (c)=> SafeArea(child: Wrap(children: [
      ListTile(leading: Icon(Icons.edit), title: Text('এডিট'), onTap: (){ Navigator.pop(c); editPatient(p); }),
      ListTile(leading: Icon(Icons.comment), title: Text('মন্তব্য'), onTap: (){ Navigator.pop(c); addComment(p); }),
      ListTile(leading: Icon(Icons.block), title: Text(p.isBlocked?'আনব্লক':'ব্লক করুন'), onTap: (){ Navigator.pop(c); toggleBlock(p); }),
      ListTile(leading: Icon(Icons.check_circle, color: Colors.green), title: Text(p.okReplied?'OK বাতিল':'OK মার্ক'), onTap: (){ Navigator.pop(c); setState((){ p.okReplied=!p.okReplied; saveAll(); applyFilter(); }); }),
      ListTile(leading: Icon(Icons.delete, color: Colors.red), title: Text('Trash'), onTap: (){ Navigator.pop(c); setState((){ p.isTrashed=true; saveAll(); applyFilter(); }); }),
    ])));
  }

  void editPatient(Patient p) {
    final nameC = TextEditingController(text: p.name);
    final mobileC = TextEditingController(text: p.mobile);
    final ageC = TextEditingController(text: p.age);
    final bkashC = TextEditingController(text: p.bkashNo);
    final txC = TextEditingController(text: p.bkashTx);
    showDialog(context: context, builder: (c)=> AlertDialog(title: Text('এডিট'), content: SingleChildScrollView(child: Column(children: [
      TextField(controller: nameC, decoration: InputDecoration(labelText: 'Name')),
      TextField(controller: mobileC, decoration: InputDecoration(labelText: 'Mobile')),
      TextField(controller: ageC, decoration: InputDecoration(labelText: 'Age')),
      TextField(controller: bkashC, decoration: InputDecoration(labelText: 'bKash No')),
      TextField(controller: txC, decoration: InputDecoration(labelText: 'bKash TX')),
    ])), actions: [TextButton(onPressed: (){
      setState((){
        p.name=nameC.text; p.mobile=mobileC.text; p.age=ageC.text; p.bkashNo=bkashC.text; p.bkashTx=txC.text;
        saveAll(); applyFilter();
      });
      Navigator.pop(c);
    }, child: Text('Save'))]));
  }

  void addComment(Patient p) {
    final c = TextEditingController(text: p.comment);
    showDialog(context: context, builder: (ctx)=> AlertDialog(title: Text('মন্তব্য'), content: TextField(controller: c, maxLines: 3), actions: [TextButton(onPressed: (){ setState((){ p.comment=c.text; saveAll(); }); Navigator.pop(ctx); }, child: Text('Save'))]));
  }

  void toggleBlock(Patient p) {
    if (p.isBlocked) { setState((){ p.isBlocked=false; saveAll(); }); return; }
    final c = TextEditingController();
    showDialog(context: context, builder: (ctx)=> AlertDialog(title: Text('ব্লক কারণ'), content: TextField(controller: c), actions: [TextButton(onPressed: (){ setState((){ p.isBlocked=true; p.blockReason=c.text; saveAll(); applyFilter(); }); Navigator.pop(ctx); }, child: Text('Block'))]));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Dr.S.Rakhi - ${DateTime.now().toString().split(' ')[0]}'), actions: [
        IconButton(icon: Icon(Icons.share), onPressed: shareWhatsApp),
        IconButton(icon: Icon(Icons.picture_as_pdf), onPressed: generatePDF),
        PopupMenuButton<String>(onSelected: (v){
          if (v=='trash') Navigator.push(context, MaterialPageRoute(builder: (_)=> TrashPage(allPatients: allPatients, onRestore: (){ loadPatients(); })));
        }, itemBuilder: (_)=> [PopupMenuItem(value: 'trash', child: Text('Trash')), PopupMenuItem(value: 'unused', child: Text('Duplicate TX'))])
      ]),
      body: Column(children: [
        Padding(padding: EdgeInsets.all(8), child: ElevatedButton.icon(icon: Icon(Icons.camera_alt), label: Text('ছবি থেকে নিন + Auto Delete'), onPressed: pickAndParse, style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity,50)))),
        Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Row(children: [
          Expanded(child: DropdownButton<String>(value: filterType, items: ['All','New','Old'].map((e)=> DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v){ setState(()=> filterType=v!); applyFilter(); })),
          SizedBox(width: 8),
          Expanded(child: TextField(decoration: InputDecoration(hintText: 'A.P. Date Filter'), onChanged: (v){ filterApDate=v; applyFilter(); })),
        ])),
        Padding(padding: EdgeInsets.all(8), child: TextField(decoration: InputDecoration(labelText: 'নাম / মোবাইল / bKash / TX সার্চ', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()), onChanged: (v){ search=v; applyFilter(); })),
        Expanded(child: ListView.builder(itemCount: filtered.length, itemBuilder: (ctx,i){
          final p = filtered[i];
          final isDup = p.bkashTx.isNotEmpty && allPatients.where((e)=> e.bkashTx==p.bkashTx).length>1;
          return Card(color: p.isBlocked?Colors.red.shade100: p.okReplied?Colors.green.shade50: null, child: ListTile(
            leading: CircleAvatar(child: Text('${p.sl}')),
            title: Text('${p.name} ${p.age.isNotEmpty?'(${p.age})':''} ${p.type} ${isDup?'⚠ DUP':''}', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${p.mobile} | ${p.bkashNo} | ${p.bkashTx} ${p.comment.isNotEmpty?'\n${p.comment}':''}'),
            trailing: p.okReplied?Icon(Icons.check_circle, color: Colors.green):null,
            onTap: ()=> showPatientOptions(p),
          ));
        }))
      ]),
    );
  }
}

class TrashPage extends StatelessWidget {
  final List<Patient> allPatients;
  final VoidCallback onRestore;
  const TrashPage({super.key, required this.allPatients, required this.onRestore});
  @override
  Widget build(BuildContext context) {
    final trashed = allPatients.where((p)=> p.isTrashed).toList();
    return Scaffold(appBar: AppBar(title: Text('Trash')), body: ListView.builder(itemCount: trashed.length, itemBuilder: (_,i){
      final p = trashed[i];
      return ListTile(title: Text(p.name), subtitle: Text(p.mobile), trailing: IconButton(icon: Icon(Icons.restore), onPressed: (){ p.isTrashed=false; onRestore(); Navigator.pop(context); }));
    }));
  }
}
