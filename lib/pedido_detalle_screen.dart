import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'chat_screen.dart';

class PedidoDetalleScreen extends StatefulWidget {
  final String idPedido;
  final String miIdActual;
  final String miRolActual; 

  const PedidoDetalleScreen({
    super.key,
    required this.idPedido,
    required this.miIdActual,
    required this.miRolActual,
  });

  @override
  State<PedidoDetalleScreen> createState() => _PedidoDetalleScreenState();
}

class _PedidoDetalleScreenState extends State<PedidoDetalleScreen> {
  bool _isLoading = false;

  Future<void> _abrirChat(String rolObjetivo) async {
    setState(() {
      _isLoading = true;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final url = Uri.parse(
          'http://192.168.0.16/dinsidescourier//buscar_o_crear_chat_por_pedido.php?id_pedido=${widget.idPedido}&rol_objetivo=$rolObjetivo');

      final response =
          await http.get(url).timeout(const Duration(seconds: 10));

      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      final jsonResponse = jsonDecode(response.body);

      if (jsonResponse['success'] == true) {
        final String idConversacion = jsonResponse['id_conversacion'].toString();

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(
                idConversacion: idConversacion,
                miId: widget.miIdActual,
                miTipo: widget.miRolActual,
                idPedido: widget.idPedido,
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('Error al iniciar chat: ${jsonResponse['message']}')),
          );
        }
      }
    } catch (e) {
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error de red: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String rolNormalizado = widget.miRolActual.toLowerCase();

    return Scaffold(
      appBar: AppBar(
        title: Text('Detalles del Pedido #${widget.idPedido}'),
        backgroundColor: Colors.blue,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Aquí van los detalles de tu pedido.',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 40),
            
            if (_isLoading)
              const CircularProgressIndicator()
            else
              Column(
                children: [
                  if (rolNormalizado == 'motorizado') ...[
                    ElevatedButton.icon(
                      icon: const Icon(Icons.person),
                      label: const Text('Chat con Cliente'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green, 
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                      ),
                      onPressed: () => _abrirChat('cliente'),
                    ),
                    const SizedBox(height: 15),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.support_agent),
                      label: const Text('Chat con Asesor'), 
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange, 
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                      ),
                      onPressed: () => _abrirChat('asesor'),
                    ),
                  ]
                  else if (rolNormalizado == 'cliente') ...[
                     ElevatedButton.icon(
                      icon: const Icon(Icons.motorcycle),
                      label: const Text('Chat con Motorizado'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                      ),
                      onPressed: () => _abrirChat('motorizado'),
                    ),
                  ]
                  else ...[
                    const Text("Rol no definido para chats")
                  ]
                ],
              ),
          ],
        ),
      ),
    );
  }
}