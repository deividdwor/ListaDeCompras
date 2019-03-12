import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_login_demo/services/authentication.dart';

// MyApp is a StatefulWidget. This allows us to update the state of the
// Widget whenever an item is removed.

class Home extends StatefulWidget {
  Home({Key key, this.auth, this.userId, this.onSignedOut}) : super(key: key);

  final BaseAuth auth;
  final VoidCallback onSignedOut;
  final String userId;

  @override
  MyAppState createState() {
    return MyAppState();
  }
}

class MyAppState extends State<Home> {
  Firestore db = Firestore.instance;
  FirebaseMessaging _firebaseMessaging = new FirebaseMessaging();
  var items = new List<Item>();
  var filtro = Status.NALISTA;
  Status mostraNalista;
  @override
  void initState() {
    super.initState();
    _firebaseMessaging.configure(
      onMessage: (Map<String, dynamic> message) {
        print('on message $message');
      },
      onResume: (Map<String, dynamic> message) {
        print('on resume $message');
      },
      onLaunch: (Map<String, dynamic> message) {
        print('on launch $message');
      },
    );
    _firebaseMessaging.getToken().then((token) {
      print(token);
    });
    _firebaseMessaging.subscribeToTopic('listaComprasApartamento');
  }

  @override
  Widget build(BuildContext context) {
    final title = 'Lista de Compras';
    ImageProvider pinguim = AssetImage('assets/pinguim.png');
    return Scaffold(
      drawer: new Drawer(
          child: new ListView(
              padding: const EdgeInsets.only(top: 0.0),
              children: <Widget>[
            new UserAccountsDrawerHeader(
              accountName: Text("Lista de compras"),
              currentAccountPicture: new CircleAvatar(
                backgroundImage: pinguim,
              ),
            ),
            new ListTile(
                leading: new Text('Na Lista'),
                onTap: () => setState(() {
                      filtro = Status.NALISTA;
                      Navigator.of(context).pop();
                    })),
            new ListTile(
                leading: new Text('Comprados'),
                onTap: () => setState(() {
                      filtro = Status.COMPRADO;
                      Navigator.of(context).pop();
                    })),
            new ListTile(
                leading: new Text('Removidos'),
                onTap: () => setState(() {
                      filtro = Status.REMOVIDO;
                      Navigator.of(context).pop();
                    })),
            new ListTile(
                leading: new Text('Todos'),
                onTap: () => setState(() {
                      filtro = null;
                      Navigator.of(context).pop();
                    })),
          ])),
      appBar: AppBar(
        title: Text(title),
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.exit_to_app),
            tooltip: 'Air it',
            onPressed: _signOut,
          ),
        ],
      ),
      floatingActionButton: new FloatingActionButton(
        onPressed: _showDialog,
        child: Icon(Icons.add),
      ),
      body: streamFirebase(),
    );
  }

  _signOut() async {
    try {
      await widget.auth.signOut();
      widget.onSignedOut();
    } catch (e) {
      print(e);
    }
  }

  streamFirebase() {
    var fi = filtro == null
        ? Firestore.instance.collection('listaCompras').snapshots()
        : Firestore.instance
            .collection('listaCompras')
            .where("status", isEqualTo: filtro.toString())
            .snapshots();
    return new StreamBuilder(
        stream: fi,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Text('Loading...');
          items.clear();
          for (DocumentSnapshot ds in snapshot.data.documents) {
            var status = Status.NALISTA;
            status = Status.values.firstWhere(
                (item) => item.toString() == ds['status'],
                orElse: () => Status.NALISTA);
            var nome = ds['nome'] != null ? ds['nome'] : '';
            var obs = ds['obs'] != null ? ds['obs'] : '';
            items.add(new Item(nome, obs, ds.documentID, status));
          }

          return ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                Item item = items[index];
                Key(item.id + item.status.toString());
                Duration(seconds: 1);

                return new Slidable(
                  delegate: new SlidableDrawerDelegate(),
                  actionExtentRatio: 0.25,
                  child: new Container(
                    color: Colors.white,
                    child: new ListTile(
                      trailing: (item.status == Status.COMPRADO
                          ? Icon(Icons.attach_money)
                          : item.status == Status.REMOVIDO
                              ? Icon(Icons.delete)
                              : Icon(Icons.local_grocery_store)),
                      title: new Text(item.nome),
                      subtitle: new Text(item.obs),
                    ),
                  ),
                  actions: <Widget>[
                    new IconSlideAction(
                      caption: item.status == Status.COMPRADO ||
                              item.status == Status.REMOVIDO
                          ? 'Voltar a Lista'
                          : 'Comprei',
                      color: item.status == Status.COMPRADO ||
                              item.status == Status.REMOVIDO
                          ? Colors.orangeAccent
                          : Colors.green,
                      icon: item.status == Status.COMPRADO ||
                              item.status == Status.REMOVIDO
                          ? Icons.local_grocery_store
                          : Icons.attach_money,
                      onTap: () => item.status == Status.COMPRADO ||
                              item.status == Status.REMOVIDO
                          ? atualizaStatus(item, Status.NALISTA)
                          : atualizaStatus(item, Status.COMPRADO),
                    ),
                  ],
                  secondaryActions: <Widget>[
                    new IconSlideAction(
                      caption: item.status == Status.REMOVIDO
                          ? 'Excluir'
                          : 'Remover',
                      color: item.status == Status.REMOVIDO
                          ? Colors.black
                          : Colors.red,
                      icon: item.status == Status.REMOVIDO
                          ? Icons.close
                          : Icons.delete,
                      onTap: () => item.status == Status.REMOVIDO
                          ? deleteNote(item.id)
                          : atualizaStatus(item, Status.REMOVIDO),
                    ),
                  ],
                );
              });
        });
  }

  Future<dynamic> deleteNote(String id) async {
    final TransactionHandler deleteTransaction = (Transaction tx) async {
      final DocumentSnapshot ds =
          await tx.get(db.collection('listaCompras').document(id));

      await tx.delete(ds.reference);
      return {'deleted': true};
    };
    return Firestore.instance
        .runTransaction(deleteTransaction)
        .then((result) => result['deleted'])
        .catchError((error) {
      print('error: $error');
      return false;
    });
  }

  Future<dynamic> updateItem(Item item) async {
    final TransactionHandler updateTransaction = (Transaction tx) async {
      final DocumentSnapshot ds =
          await tx.get(db.collection('listaCompras').document(item.id));
      var map = item.toMap();
      await tx.update(ds.reference, map);
      return {'updated': true};
    };

    return Firestore.instance
        .runTransaction(updateTransaction)
        .then((result) => result['updated'])
        .catchError((error) {
      print('error: $error');
      return false;
    });
  }

  Future<Item> createItem(Item item) async {
    final TransactionHandler createTransaction = (Transaction tx) async {
      final DocumentSnapshot ds =
          await tx.get(db.collection('listaCompras').document());

      await tx.set(ds.reference, item.toMap());

      return item.toMap();
    };

    return Firestore.instance.runTransaction(createTransaction).then((mapData) {
      return Item.fromMap(mapData);
    }).catchError((error) {
      print('error: $error');
      return null;
    });
  }

  atualizaStatus(Item item, Status status) {
    item.status = status;
    updateItem(item);
  }

  _showDialog() async {
    TextEditingController itemTxtControler = new TextEditingController();
    TextEditingController obsTxtControler = new TextEditingController();

    await showDialog<String>(
      context: context,
      child: new AlertDialog(
        contentPadding: const EdgeInsets.all(16.0),
        content: new Column(
          children: <Widget>[
            new Expanded(
              child: new TextField(
                controller: itemTxtControler,
                autofocus: true,
                decoration:
                    new InputDecoration(labelText: 'Item', hintText: 'Banana'),
              ),
            ),
            new Expanded(
              child: new TextField(
                controller: obsTxtControler,
                autofocus: true,
                decoration: new InputDecoration(
                    labelText: 'Observação', hintText: 'Não muito madura'),
              ),
            )
          ],
        ),
        actions: <Widget>[
          new FlatButton(
              child: const Text('CANCELA'),
              onPressed: () {
                Navigator.pop(context);
              }),
          new RaisedButton(
              child:
                  const Text('SALVAR', style: TextStyle(color: Colors.white)),
              onPressed: () {
                var item = Item.newItem(itemTxtControler.text,
                    obsTxtControler.text, Status.NALISTA);
                createItem(item);
                Navigator.pop(context);
              })
        ],
      ),
    );
  }
}

class Item {
  String nome;
  String id;
  Status status;
  String obs;

  Item(String nome, String obs, String id, Status status) {
    this.nome = nome;
    this.id = id;
    this.status = status;
    this.obs = obs;
  }

  Item.newItem(String nome, String obs, Status status) {
    this.nome = nome;
    this.status = status;
    this.obs = obs;
  }

  Map<String, dynamic> toMap() {
    var map = new Map<String, dynamic>();
    map['nome'] = nome;
    map['status'] = status.toString();

    map['obs'] = obs;

    return map;
  }

  Item.fromMap(Map<String, dynamic> map) {
    this.nome = map['title'];
    this.obs = map['obs'];
  }
}

enum Status { COMPRADO, REMOVIDO, NALISTA }
