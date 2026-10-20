import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:share_plus/share_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('patients');
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: HomeScreen(),
  ));
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Box box = Hive.box('patients');
  String selectedDate = DateTime.now().toString().split(' ')[0];
  TextEditingController searchCtrl = TextEditingController();

  Future<void> pickAndParse() async {
    var result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg','png','pdf']
    );
    if(result==null) return;
    File file = File(result.files.single.path!);
    final inputImage = InputImage.fromFile(file);
    final recognizer = TextRecognizer();
    final res = await recognizer.processImage(inputImage);
    await recognizer.close();
    
    int count=0;
    for(var line in res.text.split('\n')){
      var reg = RegExp(r'([A-Za-z ]+)\s+(01[0-9]{9})');
      var m = reg.firstMatch(line);
      if(m!=null){
        box.add({
          'name':m.group(1)!.trim(),
          'mobile':m.group(2)!,
          'date':selectedDate,
          'sl':box.length+1,
          'paid':false,
          'ok':false,
          'blocked':false,
          'deleted':false,
          'absent':false
        });
        count++;
      }
    }
    try{ await file.delete(); }catch(e){}
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$count জন যোগ হয়েছে, ফাইল Auto Delete হয়েছে'))
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: Text('Dr.S.Rakhi - $selectedDate')),
      body: Column(children: [
        Padding(
          padding: EdgeInsets.all(8),
          child: Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: pickAndParse,
                icon: Icon(Icons.camera),
                label: Text('ছবি/PDF থেকে নিন + Auto Delete')
              )
            ),
          ])
        ),
        Padding(
          padding: EdgeInsets.all(8),
          child: TextField(
            controller: searchCtrl,
            decoration: InputDecoration(hintText: 'নাম / মোবাইল দিয়ে সার্চ'),
            onChanged: (v){setState((){});},
          )
        ),
        Expanded(
          child: ValueListenableBuilder(
            valueListenable: box.listenable(),
            builder: (c,b,w){
              var list = b.values.where((e)=> e['deleted']==false).toList();
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (c,i){
                  var p = list[i];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Text('${p['sl']}')),
                      title: Text(p['name']),
                      subtitle: Text(p['mobile']),
                    )
                  );
                }
              );
            }
          )
        )
      ]),
    );
  }
}
