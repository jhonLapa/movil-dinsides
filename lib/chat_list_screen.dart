import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'main.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> with RouteAware {
  bool _isLoading = true;
  String? _miId;
  String? _miTipo;
  List<dynamic> _chats = [];
  List<dynamic> _chatsFiltrados = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargarSesionYChats();
    _searchController.addListener(_filtrarChats);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    _cargarSesionYChats();
  }

  Future<void> _cargarSesionYChats() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _miId = prefs.getString('mi_id');
      _miTipo = prefs.getString('mi_tipo');
    });

    if (_miId != null && _miTipo != null) {
      _fetchMyChats();
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchMyChats() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      const String baseUrl = 'http://192.168.0.16/dinsidescourier/get_my_chats.php';
      final url = Uri.parse('$baseUrl?mi_id=$_miId&mi_tipo=$_miTipo');

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        try {
          final jsonResponse = jsonDecode(response.body);
          if (jsonResponse['success'] == true) {
            if (mounted) {
              setState(() {
                _chats = jsonResponse['data'];
                _chatsFiltrados = _chats;
                _isLoading = false;
              });
            }
          } else {
            if (mounted) setState(() => _isLoading = false);
          }
        } catch (e) {
          if (mounted) setState(() => _isLoading = false);
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filtrarChats() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _chatsFiltrados = _chats.where((chat) {
        final nombre = chat['nombre_interlocutor'].toString().toLowerCase();
        return nombre.contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    const Color brandBlue = Colors.blue; 

    return Scaffold(
      appBar: AppBar(
        backgroundColor: brandBlue,
        title: const Text('Dinsides Chats', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
        ],
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          if (_miId == null && !_isLoading)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.orange[100],
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange),
                  SizedBox(width: 10),
                  Expanded(child: Text("Ingresa desde un pedido para iniciar sesión por primera vez.")),
                ],
              ),
            ),

          Container(
            color: brandBlue,
            padding: const EdgeInsets.only(bottom: 10, left: 10, right: 10),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Buscar...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.2),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _chatsFiltrados.isEmpty
                    ? const Center(child: Text("No tienes chats recientes."))
                    : ListView.builder(
                        itemCount: _chatsFiltrados.length,
                        itemBuilder: (context, index) {
                          final chat = _chatsFiltrados[index];
                          return _ChatTile(
                              chatData: chat, 
                              miId: _miId!, 
                              miTipo: _miTipo!
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final Map<String, dynamic> chatData;
  final String miId;
  final String miTipo;

  const _ChatTile({required this.chatData, required this.miId, required this.miTipo});

  @override
  Widget build(BuildContext context) {
    final String idConversacion = chatData['id_conversacion'].toString();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats/$idConversacion/mensajes')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        String ultimoMensaje = "Chat disponible";
        String hora = "";
        Widget? statusIcon;

        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
           final doc = snapshot.data!.docs.first;
           final data = doc.data() as Map<String, dynamic>;

           // Contenido
           if (data['tipo'] == 'imagen' || data['tipo'] == 'imagen_local') {
             ultimoMensaje = "📷 Imagen";
           } else {
             ultimoMensaje = data['contenido'] ?? "";
           }

           // Hora
           if (data['timestamp'] != null) {
              Timestamp ts = data['timestamp'];
              hora = _formatTimestamp(ts.toDate());
           }

           if (data['emisorId'].toString() == miId) {
               final estado = data['estado'] ?? 'enviado';
               Color color = Colors.grey;
               IconData icon = Icons.done;

               if (estado == 'visto') {
                   icon = Icons.done_all;
                   color = Colors.blue;
               } else if (estado == 'recibido') {
                   icon = Icons.done_all;
               }
               
               statusIcon = Padding(
                 padding: const EdgeInsets.only(right: 4),
                 child: Icon(icon, size: 16, color: color),
               );
           }
        } else {
            ultimoMensaje = chatData['ultimo_mensaje'] ?? "Nuevo Chat";
            hora = chatData['fecha'] ?? "";
        }

        return ListTile(
          leading: CircleAvatar(
            radius: 26,
            backgroundImage: NetworkImage(
              chatData['foto_interlocutor'] ?? 'https://i.imgur.com/d1h7XhI.png'
            ),
          ),
          title: Text(
            chatData['nombre_interlocutor'] ?? 'Usuario',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Row(
            children: [
               if (statusIcon != null) statusIcon,
               Expanded(
                 child: Text(
                   ultimoMensaje,
                   maxLines: 1,
                   overflow: TextOverflow.ellipsis,
                   style: TextStyle(
                       color: Colors.grey[600],
                   ),
                 ),
               ),
            ],
          ),
          trailing: Text(
            hora,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChatScreen(
                  idConversacion: idConversacion,
                  idPedido: chatData['id_pedido'].toString(),
                  miId: miId,
                  miTipo: miTipo,
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatTimestamp(DateTime date) {
      final now = DateTime.now();
      if (now.day == date.day && now.month == date.month && now.year == date.year) {
          return "${date.hour.toString().padLeft(2,'0')}:${date.minute.toString().padLeft(2,'0')}";
      } else {
          return "${date.day}/${date.month}";
      }
  }
}